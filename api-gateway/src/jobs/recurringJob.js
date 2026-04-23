/**
 * Tekrarlayan Görev Oluşturucu
 * Her gün 00:01'de çalışır — bugün için tekrarlayan görevleri oluşturur
 * 
 * Kullanım — app.js'e ekle:
 *   require('./jobs/recurringJob');
 */

const cron = require('node-cron');
const pool = require('../config/db');

// Bugünün tarihini YYYY-MM-DD formatında döner
function todayStr() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

// Bugün haftanın kaçıncı günü? (1=Pazartesi ... 7=Pazar)
function todayDayOfWeek() {
  const d = new Date().getDay(); // 0=Pazar
  return d === 0 ? 7 : d;
}

async function createRecurringTasksForToday() {
  const today  = todayStr();
  const dayOfWeek = todayDayOfWeek();

  // Haftanın gün adı (weekdays kontrolü için)
  const isWeekday = dayOfWeek >= 1 && dayOfWeek <= 5;

  console.log(`[RecurringJob] ${today} için tekrarlayan görevler oluşturuluyor...`);

  try {
    // Tüm tekrarlayan görevleri çek
    const [recurringTasks] = await pool.execute(
      `SELECT * FROM user_tasks 
       WHERE is_recurring = 1 
         AND status != 'cancelled'
         AND task_date <= ?`,
      [today]
    );

    let created = 0;
    let skipped = 0;

    for (const task of recurringTasks) {
      // Bu görev bugün için zaten var mı?
      const [existing] = await pool.execute(
        `SELECT id FROM user_tasks 
         WHERE user_id = ? AND name = ? AND task_date = ? AND is_recurring = 1`,
        [task.user_id, task.name, today]
      );

      if (existing.length > 0) {
        skipped++;
        continue;
      }

      // Tekrarlama tipine göre bugün oluşturulsun mu?
      let shouldCreate = false;

      if (task.recurrence_type === 'daily') {
        shouldCreate = true;
      } else if (task.recurrence_type === 'weekdays') {
        shouldCreate = isWeekday;
      } else if (task.recurrence_type === 'weekly') {
        // recurrence_days: "1,3,5" gibi — virgülle ayrılmış gün numaraları
        if (task.recurrence_days) {
          const days = task.recurrence_days.split(',').map(Number);
          shouldCreate = days.includes(dayOfWeek);
        }
      }

      if (!shouldCreate) {
        skipped++;
        continue;
      }

      // Bugün için yeni görev oluştur
      await pool.execute(
        `INSERT INTO user_tasks
           (user_id, name, address, latitude, longitude,
            duration, priority, earliest_start, latest_finish,
            task_date, status, is_recurring, recurrence_type, recurrence_days)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 1, ?, ?)`,
        [
          task.user_id, task.name, task.address,
          task.latitude, task.longitude,
          task.duration, task.priority,
          task.earliest_start, task.latest_finish,
          today,
          task.recurrence_type, task.recurrence_days,
        ]
      );
      created++;
    }

    console.log(`[RecurringJob] Tamamlandı — ${created} oluşturuldu, ${skipped} atlandı.`);
  } catch (err) {
    console.error('[RecurringJob] Hata:', err.message);
  }
}

// Her gün saat 00:01'de çalış
cron.schedule('1 0 * * *', () => {
  createRecurringTasksForToday();
}, {
  timezone: 'Europe/Istanbul',
});

// Sunucu başlarken de bir kere çalıştır (bugünkü görevleri anında oluştur)
createRecurringTasksForToday();

module.exports = { createRecurringTasksForToday };