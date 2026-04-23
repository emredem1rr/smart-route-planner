const axios = require('axios');
require('dotenv').config();

const PYTHON_URL = process.env.PYTHON_SERVICE_URL;

async function callOptimizationEngine(payload) {
  try {
    const response = await axios.post(`${PYTHON_URL}/optimize`, payload, {
      timeout: 60000,
      headers: { 'Content-Type': 'application/json' },
    });
    return response.data;
  } catch (err) {
    if (err.response) {
      throw {
        status:  err.response.status,
        message: err.response.data?.detail || 'Optimization engine error',
      };
    }
    throw {
      status:  503,
      message: 'Optimization engine is unavailable',
    };
  }
}

module.exports = { callOptimizationEngine };