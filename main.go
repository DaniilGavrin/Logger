package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Для разработки разрешаем все домены
	},
}

var db *sql.DB

// Структуры сообщений
type AuthRequest struct {
	Type     string `json:"type"`
	Username string `json:"username"`
	Password string `json:"password"`
}

type LogMessage struct {
	Type      string          `json:"type"`
	ProgramID int             `json:"program_id"`
	Level     string          `json:"level"`
	Message   string          `json:"message"`
	Metadata  json.RawMessage `json:"metadata"`
	Timestamp time.Time       `json:"timestamp"`
}

type Program struct {
	ID          int    `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	UserID      int    `json:"user_id"`
}

type User struct {
	ID       int
	Username string
}

func handleConnection(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Ошибка при апгрейде:", err)
		return
	}
	defer conn.Close()

	var currentUser *User = nil

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			log.Println("Ошибка чтения:", err)
			break
		}

		var msgBase struct {
			Type string `json:"type"`
		}
		if err := json.Unmarshal(msg, &msgBase); err != nil {
			sendError(conn, "Неверный формат сообщения")
			continue
		}

		switch msgBase.Type {
		case "auth":
			handleAuth(conn, msg, &currentUser)

		case "log":
			handleLog(conn, msg, currentUser)

		case "get_programs":
			handleGetPrograms(conn, currentUser)

		default:
			sendError(conn, "Неизвестный тип сообщения")
		}
	}
}

func handleAuth(conn *websocket.Conn, msg []byte, currentUser **User) {
	var auth AuthRequest
	if err := json.Unmarshal(msg, &auth); err != nil {
		sendError(conn, "Ошибка формата авторизации")
		return
	}

	user, err := authenticateUser(auth.Username, auth.Password)
	if err != nil {
		sendError(conn, "Неверные учетные данные")
		return
	}

	*currentUser = user
	conn.WriteJSON(map[string]interface{}{
		"type":    "auth",
		"status":  "ok",
		"message": "Авторизация успешна",
	})
	log.Printf("Авторизован: %s", user.Username)
}

func handleLog(conn *websocket.Conn, msg []byte, user *User) {
	if user == nil {
		sendError(conn, "Требуется авторизация")
		return
	}

	var logMsg LogMessage
	if err := json.Unmarshal(msg, &logMsg); err != nil {
		sendError(conn, "Ошибка формата лога")
		return
	}

	if err := insertLog(user.ID, logMsg); err != nil {
		log.Printf("Ошибка записи лога: %v", err)
		sendError(conn, "Ошибка сохранения лога")
		return
	}

	conn.WriteJSON(map[string]interface{}{
		"type":    "log",
		"status":  "ok",
		"message": "Лог сохранен",
	})
}

func handleGetPrograms(conn *websocket.Conn, user *User) {
	if user == nil {
		sendError(conn, "Требуется авторизация")
		return
	}

	log.Printf("Запрос программ для пользователя ID: %d", user.ID) // Логирование

	programs, err := getPrograms(user.ID)
	if err != nil {
		log.Printf("Ошибка получения программ: %v", err)
		sendError(conn, "Ошибка получения данных")
		return
	}

	log.Printf("Найдено программ: %d", len(programs)) // Логирование
	conn.WriteJSON(map[string]interface{}{
		"type": "programs",
		"data": programs,
	})
}

func authenticateUser(username, password string) (*User, error) {
	var user User
	query := `SELECT id, username FROM users WHERE username = ? AND password = ?`
	err := db.QueryRow(query, username, password).Scan(&user.ID, &user.Username)
	if err != nil {
		return nil, fmt.Errorf("ошибка аутентификации: %w", err)
	}
	return &user, nil
}

func insertLog(userID int, logMsg LogMessage) error {
	query := `INSERT INTO logs (program_id, user_id, timestamp, level, message, metadata)
              VALUES (?, ?, ?, ?, ?, ?)`
	_, err := db.Exec(query,
		logMsg.ProgramID,
		userID,
		logMsg.Timestamp.Format(time.RFC3339),
		logMsg.Level,
		logMsg.Message,
		logMsg.Metadata,
	)
	return err
}

func getPrograms(userID int) ([]Program, error) {
	rows, err := db.Query(`
        SELECT id, name, description, user_id 
        FROM programs 
        WHERE user_id = ?
    `, userID)
	if err != nil {
		return nil, fmt.Errorf("ошибка запроса: %w", err)
	}
	defer rows.Close()

	var programs []Program
	for rows.Next() {
		var p Program
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.UserID); err != nil {
			return nil, fmt.Errorf("ошибка сканирования: %w", err)
		}
		programs = append(programs, p)
	}
	return programs, nil
}

func sendError(conn *websocket.Conn, message string) {
	conn.WriteJSON(map[string]string{
		"type":    "error",
		"message": message,
	})
}

func main() {
	var err error
	db, err = sql.Open("mysql", "root:0000@tcp(localhost:3306)/Logger?parseTime=true")
	if err != nil {
		log.Fatal("Ошибка подключения к БД:", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatal("Проверка соединения с БД не удалась:", err)
	}

	http.HandleFunc("/ws", handleConnection)

	log.Println("Сервер запущен на ws://localhost:8080/ws")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
