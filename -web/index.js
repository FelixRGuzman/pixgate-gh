require('dotenv').config();
const express = require('express');
const mysql = require('mysql2');
const path = require('path');
const { spawn } = require('child_process'); // Spawner tool
const app = express();

app.use(express.json());
app.use(express.static('public'));

// CONFIGURATION
// Path to your exported console executable
const GODOT_PATH = "C:/Users/vaeli/OneDrive/Documents/pixgate-gh/Pixgate.console.exe";

// Object to track running world processes so we can kill them on logout
const activeProcesses = {};

// Database Connection Pool
const db = mysql.createPool({
    host: 'localhost',
    user: 'root',
    password: process.env.DB_PASSWORD,
    database: 'pixgate_db',
    waitForConnections: true,
    connectionLimit: 10
}).promise();

// AUTH: REGISTER
app.post('/api/register', async (req, res) => {
    const { username, password } = req.body;
    console.log(`[Registration Attempt] User: ${username}`);
    if (!username || !password) {
        console.log("  -> Failed: Missing fields");
        return res.status(400).json({ error: "Username and password are required." });
    }
    try {
        const [existing] = await db.query('SELECT id FROM users WHERE username = ?', [username]);
        if (existing.length > 0) {
            console.log(`  -> Failed: Username '${username}' already exists.`);
            return res.status(400).json({ error: "Username already taken." });
        }
        const [result] = await db.query(
            'INSERT INTO users (username, password, color) VALUES (?, ?, ?)',
            [username, password, '#3498db']
        );
        console.log(`  -> Success! New ID: ${result.insertId}`);
        res.json({ success: true });
    } catch (err) {
        console.error("  -> DATABASE ERROR:", err.message);
        res.status(500).json({ error: "Internal Server Error" });
    }
});

// AUTH: LOGIN 
app.post('/api/login', async (req, res) => {
    const { username, password } = req.body;
    try {
        const [rows] = await db.query('SELECT username, color FROM users WHERE username = ? AND password = ?', [username, password]);
        if (rows.length === 0) return res.status(401).json({ error: "Invalid credentials" });
        console.log(`[Login] User authorized: ${username}`);
        res.json(rows[0]);
    } catch (err) {
        res.status(500).json({ error: "Database error" });
    }
});

// LOBBY: HOST A GAME (PERSISTENT SPAWNER) 
app.post('/api/host-game', async (req, res) => {
    const { username, mode, manualIp } = req.body;
    let ip = (mode === 'auto') ? (req.headers['x-forwarded-for'] || req.socket.remoteAddress) : '127.0.0.1';

    try {
        if (activeProcesses[username]) {
            activeProcesses[username].kill();
            delete activeProcesses[username];
        }

        console.log(`[Spawner] Attempting to launch: ${GODOT_PATH}`);

        // SPAWN with error handling
        // Add 'cwd' so the EXE can find its .pck file
        const godot = spawn(GODOT_PATH, ["--headless"], {
            cwd: "C:/Users/vaeli/OneDrive/Documents/pixgate-gh"
        });

        // This triggers if the path is wrong or permissions are denied
        godot.on('error', (err) => {
            console.error(`[CRITICAL ERROR] Failed to start Godot: ${err.message}`);
        });

        activeProcesses[username] = godot;

        godot.stdout.on('data', (data) => console.log(`[Godot ${username}]: ${data}`));
        godot.stderr.on('data', (data) => console.error(`[Godot ERROR ${username}]: ${data}`));

        await db.query('DELETE FROM active_servers WHERE host_name = ?', [username]);
        await db.query('INSERT INTO active_servers (host_name, ip_address) VALUES (?, ?)', [username, ip]);

        console.log(`[Lobby] ${username} spawned a background world @ ${ip}`);
        res.json({ success: true, detected_ip: ip });

    } catch (err) {
        console.error("[Lobby Error]", err.message);
        res.status(500).json({ error: "Could not spawn world process" });
    }
});

// LOBBY: STOP HOSTING
app.post('/api/stop-hosting', async (req, res) => {
    const { username } = req.body;
    try {
        if (activeProcesses[username]) {
            activeProcesses[username].kill();
            delete activeProcesses[username];
        }

        const [result] = await db.query('DELETE FROM active_servers WHERE host_name = ?', [username]);
        if (result.affectedRows > 0) {
            console.log(`[Lobby] ${username} closed their world.`);
        }
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: "Cleanup error" });
    }
});

// LOBBY: GET ACTIVE SERVERS 
app.get('/api/servers', async (req, res) => {
    try {
        const [rows] = await db.query('SELECT host_name, ip_address FROM active_servers');
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: "Could not fetch servers" });
    }
});

// PLAYER: UPDATE COLOR
app.post('/api/update-profile', async (req, res) => {
    const { username, color } = req.body;
    try {
        await db.query('UPDATE users SET color = ? WHERE username = ?', [color, username]);
        console.log(`[Profile] ${username} changed color to ${color}`);
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: "DB Error" });
    }
});

// LOGOUT & CLEANUP
app.post('/api/logout', async (req, res) => {
    const { username } = req.body;
    try {
        if (activeProcesses[username]) {
            activeProcesses[username].kill();
            delete activeProcesses[username];
        }

        await db.query('DELETE FROM active_servers WHERE host_name = ?', [username]);
        console.log(`[Logout] ${username} left the universe.`);
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: "Logout error" });
    }
});

// Godot client fetch data for GameManager initialization
app.get('/api/player/:username', async (req, res) => {
    try {
        const [rows] = await db.query('SELECT username, color FROM users WHERE username = ?', [req.params.username]);
        if (rows.length === 0) return res.status(404).json({ error: "User not found" });
        res.json(rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.listen(3000, () => {
    console.log("-----------------------------------------");
    console.log("PIXGATE READY: http://localhost:3000");
    console.log("-----------------------------------------");
});
