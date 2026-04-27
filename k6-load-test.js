import http from "k6/http";
import { check, sleep } from "k6";
import { Counter, Rate, Trend } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";

const writeErrors = new Counter("write_errors");
const readCacheHit = new Rate("read_cache_hit_rate");
const writeDuration = new Trend("write_duration_ms", true);

export const options = {
  stages: [
    { duration: "30s", target: 50 },
    { duration: "1m",  target: 200 },
    { duration: "2m",  target: 500 },
    { duration: "3m",  target: 1000 },
    { duration: "1m",  target: 1000 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    http_req_duration: ["p(95)<500", "p(99)<1500"],
    http_req_failed:   ["rate<0.01"],
    write_errors:      ["count<50"],
  },
};

function randomId(max) {
  return Math.floor(Math.random() * max) + 1;
}

export default function () {
  const roll = Math.random();

  if (roll < 0.70) {
    // leitura paginada — cache quente
    const res = http.get(`${BASE_URL}/api/products?page=0&size=20`);
    const ok = check(res, { "list 200": (r) => r.status === 200 });
    readCacheHit.add(ok);

  } else if (roll < 0.85) {
    // leitura por ID
    const id = randomId(500);
    const res = http.get(`${BASE_URL}/api/products/${id}`);
    check(res, { "getById 200|404": (r) => r.status === 200 || r.status === 404 });

  } else {
    // escrita
    const payload = JSON.stringify({
      name:  `Product-${Date.now()}`,
      price: (Math.random() * 1000).toFixed(2),
      stock: Math.floor(Math.random() * 100),
    });

    const start = Date.now();
    const res = http.post(`${BASE_URL}/api/products`, payload, {
      headers: { "Content-Type": "application/json" },
    });
    writeDuration.add(Date.now() - start);

    const ok = check(res, { "create 201": (r) => r.status === 201 });
    if (!ok) writeErrors.add(1);
  }

  sleep(0.1);
}
