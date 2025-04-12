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
		return true // Разрешаем все origin для разработки
	},
	HandshakeTimeout: 10 * time.Second, // Таймаут на установку соединения
}

var db *sql.DB

// Структуры данных
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

func main() {
	var err error
	// Инициализация подключения к БД
	db, err = sql.Open("mysql", "root:0000@tcp(localhost:3306)/Logger?parseTime=true")
	if err != nil {
		log.Fatal("Ошибка подключения к БД:", err)
	}
	defer db.Close()

	// Проверка соединения с БД
	if err := db.Ping(); err != nil {
		log.Fatal("Проверка соединения с БД не удалась:", err)
	}

	// Настройка HTTP маршрутов
	http.HandleFunc("/ws", handleConnection)

	log.Println("🚀 Сервер запущен на ws://localhost:8080/ws")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func handleConnection(w http.ResponseWriter, r *http.Request) {
	log.Println("🔌 Новое соединение")

	// Апгрейд соединения до WebSocket
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("❌ Ошибка при апгрейде:", err)
		return
	}
	defer conn.Close()

	conn.SetReadLimit(1048576) // 1MB
	conn.SetWriteDeadline(time.Now().Add(30 * time.Second))

	// Измените обработчик Pong
	conn.SetPongHandler(func(string) error {
		conn.SetWriteDeadline(time.Now().Add(30 * time.Second))
		return nil
	})

	conn.SetCloseHandler(func(code int, text string) error {
		log.Printf("🔌 Соединение закрыто клиентом: %d %s", code, text)
		return nil
	})

	// Запуск ping-отправителя
	stopPing := make(chan struct{})
	defer close(stopPing)
	go pingSender(conn, stopPing)

	var currentUser *User

	// Основной цикл обработки сообщений
	for {
		conn.SetReadDeadline(time.Now().Add(30 * time.Second))
		_, msg, err := conn.ReadMessage()
		if err != nil {
			handleReadError(err)
			break
		}

		processMessage(conn, msg, &currentUser)
	}
}

func pingSender(conn *websocket.Conn, stop <-chan struct{}) {
	ticker := time.NewTicker(25 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			sendPing(conn)
		case <-stop:
			return
		}
	}
}

func sendPing(conn *websocket.Conn) {
	if err := conn.WriteControl(
		websocket.PingMessage,
		[]byte{},
		time.Now().Add(5*time.Second),
	); err != nil {
		log.Println("⚠️ Ошибка отправки Ping:", err)
		return
	}
	log.Println("🏓 Отправлен Ping")
}

func handleReadError(err error) {
	if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
		log.Printf("⚠️ Ошибка чтения: %v", err)
	}
}

func processMessage(conn *websocket.Conn, msg []byte, user **User) {
	log.Printf("📨 Получено сообщение: %s\n", string(msg))

	var base struct{ Type string }
	if err := json.Unmarshal(msg, &base); err != nil {
		sendError(conn, "Неверный формат сообщения")
		return
	}

	switch base.Type {
	case "ping": // Добавлен обработчик ping
		handlePing(conn)
	case "auth":
		handleAuth(conn, msg, user)
	case "log":
		handleLog(conn, msg, *user)
	case "get_programs":
		handleGetPrograms(conn, *user)
	case "get_logs":
		handleGetLogs(conn, msg)
	default:
		sendError(conn, "Неизвестный тип сообщения")
	}
}

func handlePing(conn *websocket.Conn) {
	log.Println("🏓 Получен Ping от клиента")
	sendJSON(conn, map[string]string{
		"type": "pong",
	})
}

func handleAuth(conn *websocket.Conn, msg []byte, user **User) {
	var auth AuthRequest
	if err := json.Unmarshal(msg, &auth); err != nil {
		sendError(conn, "Ошибка формата авторизации")
		return
	}

	u, err := authenticateUser(auth.Username, auth.Password)
	if err != nil {
		sendError(conn, "Неверные учетные данные")
		return
	}

	*user = u
	sendSuccess(conn, "auth", "Авторизация успешна")
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
		sendError(conn, "Ошибка сохранения лога")
		return
	}

	sendSuccess(conn, "log", "Лог сохранен")
}

func handleGetPrograms(conn *websocket.Conn, user *User) {
	if user == nil {
		sendError(conn, "Требуется авторизация")
		return
	}

	programs, err := getPrograms(user.ID)
	if err != nil {
		sendError(conn, "Ошибка получения данных")
		return
	}

	sendJSON(conn, map[string]interface{}{
		"type": "programs",
		"data": programs,
	})
}

func handleGetLogs(conn *websocket.Conn, msg []byte) {
	var req struct {
		ProgramID int `json:"program_id"`
	}

	if err := json.Unmarshal(msg, &req); err != nil {
		sendError(conn, "Неверный формат запроса")
		return
	}

	logs, err := fetchLogs(req.ProgramID)
	if err != nil {
		sendError(conn, "Ошибка получения логов")
		return
	}

	sendJSON(conn, map[string]interface{}{
		"type": "logs",
		"data": logs,
	})
}

// Database functions
func authenticateUser(username, password string) (*User, error) {
	var user User
	err := db.QueryRow(
		"SELECT id, username FROM users WHERE username = ? AND password = ?",
		username, password,
	).Scan(&user.ID, &user.Username)

	if err != nil {
		return nil, fmt.Errorf("ошибка аутентификации: %w", err)
	}
	return &user, nil
}

func insertLog(userID int, logMsg LogMessage) error {
	_, err := db.Exec(
		`INSERT INTO logs 
		(program_id, user_id, timestamp, level, message, metadata) 
		VALUES (?, ?, ?, ?, ?, ?)`,
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
		WHERE user_id = ?`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var programs []Program
	for rows.Next() {
		var p Program
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.UserID); err != nil {
			return nil, err
		}
		programs = append(programs, p)
	}
	return programs, nil
}

func fetchLogs(programID int) ([]LogMessage, error) {
	// 1. Добавляем program_id в SELECT
	rows, err := db.Query(`
        SELECT program_id, timestamp, level, message, metadata 
        FROM logs 
        WHERE program_id = ? 
        ORDER BY timestamp DESC 
        LIMIT 100`,
		programID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var logs []LogMessage
	for rows.Next() {
		var l LogMessage
		var ts string
		var metadata sql.NullString

		// 2. Сканируем program_id из результата запроса
		if err := rows.Scan(
			&l.ProgramID, // Добавлено поле program_id
			&ts,
			&l.Level,
			&l.Message,
			&metadata,
		); err != nil {
			return nil, err
		}

		l.Timestamp, _ = time.Parse(time.RFC3339, ts)
		if metadata.Valid {
			l.Metadata = json.RawMessage(metadata.String)
		}
		logs = append(logs, l)
	}
	return logs, nil
}

// Helpers
func sendError(conn *websocket.Conn, message string) {
	log.Printf("⚠️ Ошибка: %s", message)
	sendJSON(conn, map[string]string{
		"type":    "error",
		"message": message,
	})
}

func sendSuccess(conn *websocket.Conn, msgType, message string) {
	sendJSON(conn, map[string]string{
		"type":    msgType,
		"status":  "ok",
		"message": message,
	})
}

func sendJSON(conn *websocket.Conn, data interface{}) {
	if err := conn.WriteJSON(data); err != nil {
		log.Println("❌ Ошибка отправки ответа:", err)
	}
}
