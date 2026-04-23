# Smart Route Planner

AI-powered route optimization app built with Flutter, Node.js, and Python.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Flutter Mobile App                     │
│         (Android / iOS — Dart + flutter_map)            │
└───────────────────┬─────────────────────────────────────┘
                    │ HTTP
          ┌─────────▼──────────┐
          │   API Gateway       │
          │   Node.js / Express │  :3000
          │   JWT Auth, MySQL   │
          └─────────┬──────────┘
                    │ HTTP
          ┌─────────▼──────────────────────────────────┐
          │        Optimization Engine                   │
          │        Python / FastAPI          :8000       │
          │                                             │
          │  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
          │  │ /optimize│  │/benchmark│  │ /suggest │  │
          │  └──────────┘  └──────────┘  └──────────┘  │
          │                                             │
          │  Algorithms: Genetic · SA · ACO · Tabu · LKH│
          │  AI: Gemini Flash → Ollama/Mistral → fallback│
          └────────────────────┬────────────────────────┘
                               │
              ┌────────────────┼─────────────────┐
              │                │                 │
     ┌────────▼────┐  ┌────────▼────┐  ┌────────▼────┐
     │  MySQL DB   │  │ Google Maps │  │  Gemini AI  │
     │  (schema.sql│  │ Places API  │  │  Flash      │
     └─────────────┘  └─────────────┘  └─────────────┘
```

## Setup

### 1. Database

```bash
mysql -u root -p < database/schema.sql
mysql -u root -p smart_route_planner < database/update.sql
```

### 2. API Gateway (Node.js)

```bash
cd api-gateway
cp .env.example .env       # fill in your values
npm install
npm run dev
```

### 3. Optimization Engine (Python)

```bash
cd optimization-engine
python -m venv venv
venv\Scripts\activate       # Windows
pip install -r requirements.txt
cp .env.example .env        # fill in GEMINI_API_KEY etc.
uvicorn app.main:app --reload --port 8000
```

### 4. Flutter App

```bash
cd mobile
flutter pub get
flutter run
```

For a real device on the same WiFi, edit `lib/core/constants/api_constants.dart` and set `pcIp` to your PC's local IP.

## Environment Variables

| Service | Variable | Description |
|---|---|---|
| api-gateway | `DB_HOST` | MySQL host |
| api-gateway | `JWT_SECRET` | JWT signing secret |
| api-gateway | `EMAIL_USER/PASS` | Gmail SMTP credentials |
| optimization-engine | `GEMINI_API_KEY` | Google Gemini API key |
| optimization-engine | `GOOGLE_MAPS_API_KEY` | For traffic-aware routing |
| optimization-engine | `OLLAMA_URL` | Ollama server (fallback AI) |

## Features

- **Route Optimization**: 5 algorithms compared — Genetic, Simulated Annealing, ACO, Tabu Search, Lin-Kernighan
- **AI Suggestions**: Gemini Flash-powered city exploration with smart place scoring
- **AI Filters**: Review-based analysis for child-friendly, vegan, pet-friendly etc.
- **Natural Language Search**: "çocuklu aileler için sessiz kafe İstanbul Kadıköy"
- **Benchmark**: Berlin52, kroA100, pr76 TSP datasets with gap% vs optimal
- **Traffic Routing**: Google Distance Matrix API with departure_time=now
- **Offline Support**: Local SQLite + offline map tiles
