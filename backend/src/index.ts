import express, { Request, Response, NextFunction } from 'express';
import axios from 'axios';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import https from 'https';
import fs from 'fs';

// Load environment variables from .env file
dotenv.config();

const app = express();
const PORT = process.env.PORT || 443;

const GOOGLE_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
const HIGGS_API_URL = 'http://45.67.213.138:20023/v1/audio/speech';

// --- Middleware Setup ---
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

// --- API Proxy Route for Google ---
const prepareGoogleProxy = (req: Request, res: Response, next: NextFunction) => {
  const apiKey = process.env.GOOGLE_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'API key is not configured on the server.' });
  }
  res.locals.proxyHeaders = {
    'Content-Type': req.header('Content-Type') || 'application/json',
    'x-goog-api-key': apiKey,
  };
  next();
};

app.post('/llm', prepareGoogleProxy, async (req: Request, res: Response) => {
  console.log('➡️  Received new request for /llm');
  
  const timestamp = new Date().toISOString();
  const logEntry = {
    timestamp,
    request: {
      headers: req.headers,
      body: req.body
    },
    response: null as any,
    error: null as any
  };

  try {
    const response = await axios.post(
      GOOGLE_API_URL,
      req.body,
      { headers: res.locals.proxyHeaders }
    );
    
    // Log the response
    logEntry.response = {
      status: response.status,
      headers: response.headers,
      body: response.data
    };
    
    // Write to log file
    const logPath = path.join(__dirname, '../logs');
    if (!fs.existsSync(logPath)) {
      fs.mkdirSync(logPath, { recursive: true });
    }
    
    const logFile = path.join(logPath, `llm-${new Date().toISOString().split('T')[0]}.log`);
    fs.appendFileSync(logFile, JSON.stringify(logEntry, null, 2) + '\n---\n');
    
    res.status(response.status).json(response.data);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    console.error('❌ Error from Google API:', axios.isAxiosError(error) ? error.response?.data : errorMessage);
    
    // Log the error
    logEntry.error = {
      message: errorMessage,
      response: axios.isAxiosError(error) && error.response ? {
        status: error.response.status,
        data: error.response.data
      } : null
    };
    
    // Write error to log file
    const logPath = path.join(__dirname, '../logs');
    if (!fs.existsSync(logPath)) {
      fs.mkdirSync(logPath, { recursive: true });
    }
    
    const logFile = path.join(logPath, `llm-${new Date().toISOString().split('T')[0]}.log`);
    fs.appendFileSync(logFile, JSON.stringify(logEntry, null, 2) + '\n---\n');
    
    if (axios.isAxiosError(error) && error.response) {
      res.status(error.response.status).json(error.response.data);
    } else {
      res.status(500).json({ error: 'An internal server error occurred.' });
    }
  }
});

// --- NEW: API Proxy Route for Higgs Audio ---
app.post('/higgs', async (req: Request, res: Response) => {
  console.log('➡️  Received new request for /higgs audio stream');
  try {
    const response = await axios.post(
      HIGGS_API_URL,
      req.body, // Forwarding the incoming body
      {
        headers: {
          // The target API likely expects a JSON body
          'Content-Type': 'application/json',
        },
        // IMPORTANT: This tells axios to handle the response as a stream
        responseType: 'stream',
      }
    );

    // Forward the headers from the Higgs API response (e.g., Content-Type: audio/...)
    res.writeHead(response.status, response.headers);

    // Pipe the audio stream directly to the client's response
    response.data.pipe(res);

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    console.error('❌ Error from Higgs API:', axios.isAxiosError(error) ? error.response?.data : errorMessage);
    if (axios.isAxiosError(error) && error.response) {
      // If the error response is a stream, we can't easily read it as JSON.
      // We send back the status code and a generic error.
      res.status(error.response.status).json({
        error: 'Error from audio generation service.',
        details: 'See proxy server logs for more information.'
      });
    } else {
      res.status(500).json({ error: 'An internal server error occurred.' });
    }
  }
});



const options = {
  key: fs.readFileSync(path.join(__dirname, '../key.pem')),   // Path to your key
  cert: fs.readFileSync(path.join(__dirname, '../cert.pem')), // Path to your certificate
};

https.createServer(options, app).listen(PORT, () => {
  console.log(`✅ Server is running at https://0.0.0.0:${PORT}`);
});
