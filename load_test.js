import http from 'k6/http';
import { check, sleep } from 'k6';

// 1. КОНФИГУРАЦИЯ ТЕСТА
export const options = {
  // Этапы нагрузки
    stages: [
        { duration: '30s', target: 20 },  // Разгон 30 сек
        { duration: '3m', target: 50 },   // 3 минуты держим нагрузку (чтобы AWS нарисовал линию)
        { duration: '30s', target: 0 },   // Плавная остановка
    ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% запросов должны быть быстрее 500мс
  },
};

// 2. ТЕЛО ЗАПРОСА
export default function () {
  const url = 'https://i5olri2bdh.execute-api.eu-west-1.amazonaws.com/dev/orders'; // <--- ВСТАВЬ СЮДА СВОЙ URL
  
  // Генерируем случайную цену и количество, чтобы данные были разными
  const price = (Math.random() * 1000 + 40000).toFixed(2);
  const amount = (Math.random() * 2).toFixed(4);
  const side = Math.random() > 0.5 ? 'BUY' : 'SELL';

  const payload = JSON.stringify({
    pair: 'BTC_USD',
    side: side,
    price: parseFloat(price),
    amount: parseFloat(amount),
    user_id: 'load-tester-bot'
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  // 3. ОТПРАВКА ЗАПРОСА
  const res = http.post(url, payload, params);

  // 4. ПРОВЕРКА (Успешно ли?)
  check(res, {
    'is status 200': (r) => r.status === 200,
  });

  sleep(0.1); // Небольшая пауза между запросами (100мс)
}