import express, { Request, Response, NextFunction } from 'express';
import axios from 'axios';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';

// Load environment variables from .env file
dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

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
  try {
    const response = await axios.post(
      GOOGLE_API_URL,
      req.body,
      { headers: res.locals.proxyHeaders }
    );
    res.status(response.status).json(response.data);
  } catch (error) {
    console.error('❌ Error from Google API:', error.response?.data || error.message);
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
    console.error('❌ Error from Higgs API:', error.response?.data || error.message);
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


// --- Start Server ---
app.listen(PORT, () => {
  console.log(`✅ Server is running at http://localhost:${PORT}`);
});
