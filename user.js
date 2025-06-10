const jwt = require('jsonwebtoken');
const express = require('express');
const router = express.Router();

let users = []; // Simple in-memory array to store users

// Register
router.post('/register', (req, res) => {
  const { username, password } = req.body;
  const userExists = users.find(u => u.username === username);
  if (userExists) {
    return res.status(400).json({ message: 'User already exists' });
  }
  users.push({ username, password });
  res.json({ message: 'User registered successfully' });
});

// Login user
router.post('/login', (req, res) => {
    const { username, password } = req.body;
    const user = users.find(u => u.username === username);
    if (!user || user.password !== password) {
      return res.status(401).json({ message: 'Invalid credentials' });
    }
  
    const token = jwt.sign({ username }, 'kavi_secreat', { expiresIn: '1h' });
    res.json({ message: 'Login successful', token });
  });

module.exports = router;