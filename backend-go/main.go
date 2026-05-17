package main

import (
	"bytes"
	"database/sql"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"
)

type User struct {
	ID					string `json:"user_id"`
	UserName 			string `json:"user_name"`
	Email				string `json:"email"`
	PasswordHash		string `json:"-"`
	PhoneNumber     	string `json:"phone_number"`
	Role				string `json:"role"`
	CurrentCompany		string `json:"current_company"`
	Specialization		string `json:"specialization"`
}

type CVSubmission struct {
    UserID    string `json:"user_id"`
    ExpertID  string `json:"expert_id"`
    FileURL   string `json:"file_url"`
    Status    string `json:"status"`
}

func CORSMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        // allows phone/emulator to talk to the server
        c.Writer.Header().Set("Access-Control-Allow-Origin", "*") 
        c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
        c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
        c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT")

        // check handling
        if c.Request.Method == "OPTIONS" {
            c.AbortWithStatus(204)
            return
        }

        c.Next()
    }
}

var db *sql.DB

func main(){
	err := godotenv.Load()
	if err != nil {
		log.Println("Warning: No .env file found. Falling back to system environment variables.")
	}

	hub := NewHub()
	go hub.Run()
	connStr := os.Getenv("DB_CONN_STR")

	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}

	if err = db.Ping(); err != nil {
		log.Fatal("Database unreachable:", err)
	}

	// 2. Setup Routes
	r := gin.Default()

	r.GET("/ping", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "Backend is up!"})
	})

	r.Use(CORSMiddleware())

	// WEBSOCKET
	r.GET("/ws", func(c *gin.Context) {
		serveWs(hub, c.Writer, c.Request)
	})

	// POST: Register and Login
	r.GET("/profile/:id", GetUserProfile)
	r.POST("/register", RegisterUser)
	r.POST("/login", LoginUser)
	r.POST("/submit-cv", SubmitCV)
	r.POST("/upload", UploadToStorage)

	// GET: Experts
	r.GET("/experts", GetExperts)

	// 4. Start Server
	r.Run(":8080")
}

// REGISTER USER
func RegisterUser (c *gin.Context) {
	var input struct {
		UserName		string `json:"user_name"`
		Email			string `json:"email"`
		Password		string `json:"password"`
		PhoneNumber		string `json:"phone_number"`
		Role			string `json:"role"`
		CurrentCompany 	string `json:"current_company"`
		Specialization 	string `json:"specialization"`
	}

	// parse the json
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	
	// hash the password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash password"})
		return
	}

	// insert into the supabase
	query := `INSERT INTO users (user_name, email, password_hash, phone_number, role, current_company, specialization) 
              VALUES ($1, $2, $3, $4, $5, $6, $7) 
              RETURNING user_id`
    
    // 2. Create a variable to hold the new ID
    var newID string

    // 3. Use QueryRow instead of Exec so we can .Scan() the ID into our variable
    err = db.QueryRow(query, 
        input.UserName, 
        input.Email, 
        string(hashedPassword), 
        input.PhoneNumber, 
        input.Role, 
        input.CurrentCompany, 
        input.Specialization,
    ).Scan(&newID)

    if err != nil {
        fmt.Println("DATABASE ERROR:", err) 
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    // 4. Now use that newID variable in your response
    c.JSON(201, gin.H{
        "message": "User created successfully",
        "user_id": newID, 
    })
}

func LoginUser (c *gin.Context) {
	var loginReq struct {
		Email		string `json:"email"`
		Password	string `json:"password"`
	}

	if err := c.ShouldBindJSON(&loginReq); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var storedHash string
	var userID string
	query := `SELECT user_id, password_hash FROM users WHERE email = $1`
	err := db.QueryRow(query, loginReq.Email).Scan(&userID, &storedHash)

	// if email invalid
    if err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid email or password"})
        return
    }

	// if password invalid
	err = bcrypt.CompareHashAndPassword([]byte(storedHash), []byte(loginReq.Password))
    if err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid email or password"})
        return
    }

	// success!
	c.JSON(http.StatusOK, gin.H{
        "message": "Login successful!",
        "user_id": userID,
    })
}

func GetExperts (c *gin.Context) {
	rows, err := db.Query("SELECT user_id, user_name, current_company, specialization FROM users WHERE role = 'expert'")
	
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
	}
	defer rows.Close()

	var experts []map[string]interface{}
    for rows.Next() {
        var id, name, company, spec string
        rows.Scan(&id, &name, &company, &spec)
        experts = append(experts, map[string]interface{}{
            "id":              id,
            "name":            name,
            "current_company": company,
            "specialization":  spec,
        })
    }

	c.JSON(http.StatusOK, experts)
}

func SubmitCV (c *gin.Context) {
	var req struct {
        StudentID string `json:"student_id"`
        ExpertID  string `json:"expert_id"`
        FileURL   string `json:"file_url"`
    }

	if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid data format"})
        return
    }

	var lastInsertID string
	query := `INSERT INTO review_request (student_id, expert_id, file_url, status) 
			VALUES ($1, $2, $3, 'pending') RETURNING id`

	err := db.QueryRow(query, req.StudentID, req.ExpertID, req.FileURL).Scan(&lastInsertID)

	if err != nil {
        fmt.Println("DEBUG: SubmitCV DB Error ->", err)

		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save submission"})
        return
    }

	c.JSON(http.StatusOK, gin.H{
        "message": "CV submitted successfully for review!",
        "status":  "pending",
    })
}

func GetUserProfile(c *gin.Context) {
    id := c.Param("id") 
    
    fmt.Println("Searching for ID:", id)

    var name, role, spec, company string
    
    // 2. We use $1 as the placeholder for the first variable (id)
    err := db.QueryRow("SELECT user_name, role, specialization, current_company FROM users WHERE user_id = $1::uuid", id).
    	Scan(&name, &role, &spec, &company)

    if err != nil {
        fmt.Println("Database Error:", err)
        c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
        return
    }

    c.JSON(http.StatusOK, gin.H{
        "user_name":      name,
        "role":           role,
        "specialization": spec,
        "company":        company,
    })
}

func UploadToStorage(c *gin.Context) {
	header, err := c.FormFile("file")

	if (err != nil) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No file received"})
		return
	}

	// explicitly open the file from the header to read its binary data
	file, err := header.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to open received file"})
		return
	}

	defer file.Close()

	// ensure only pdf format
	if filepath.Ext(header.Filename) != ".pdf" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only PDF files are allowed"})
		return
	}

	buf := bytes.NewBuffer(nil)
	if _, err := io.Copy(buf, file); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to parse file content"})
		return
	}

	// generate a unique file name
	uniqueFilename := fmt.Sprintf("%d_%s", time.Now().UnixNano(), header.Filename)
	supabaseURL := os.Getenv("SUPABASE_URL")
	supabaseKey := os.Getenv("SUPABASE_KEY")

	uploadURL := fmt.Sprintf("%s/storage/v1/object/resumes/%s", supabaseURL, uniqueFilename)

	// request to post
	req, err := http.NewRequest("POST", uploadURL, buf)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to formulate upstream request"})
		return
	}

	req.Header.Set("Authorization", "Bearer "+supabaseKey)
	req.Header.Set("ApiKey", supabaseKey)
	req.Header.Set("Content-Type", "application/pdf")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Supabase connection refused"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":  "Supabase Storage engine error response",
			"detail": string(bodyBytes),
		})
		return
	}

	// accessible public download link
	publicURL := fmt.Sprintf("%s/storage/v1/object/public/resumes/%s", supabaseURL, uniqueFilename)

	c.JSON(http.StatusOK, gin.H{
		"message":  "File uploaded to cloud bucket successfully!",
		"file_url": publicURL,
	})
}