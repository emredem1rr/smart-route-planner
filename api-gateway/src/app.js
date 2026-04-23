require('dotenv').config();
require('./config/db');
require('./jobs/recurringJob');
const express       = require('express');
const cors          = require('cors');
const authRoutes    = require('./routes/authRoutes');
const optimizeRoutes = require('./routes/optimizeRoutes');
const placesRoutes = require('./routes/placesRoutes');
const app  = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());
app.use('/api', authRoutes);
app.use('/api', optimizeRoutes);

app.use('/api', placesRoutes);
app.get('/health', (_, res) => res.json({ status: 'ok' }));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`API Gateway running on port ${PORT}`);
});