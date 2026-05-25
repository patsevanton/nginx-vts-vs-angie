import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const latencyP95 = new Trend('latency_p95');
const latencyP99 = new Trend('latency_p99');
const ttfbP95 = new Trend('ttfb_p95');
const throughputBytes = new Trend('throughput_bytes');

const TARGETS = {
  'nginx-vts-docker': __ENV.TARGET_NGINX_VTS_DOCKER || 'localhost',
  'nginx-vts': __ENV.TARGET_NGINX_VTS || 'localhost',
  'angie': __ENV.TARGET_ANGIE || 'localhost',
};

const VARIANT = __ENV.VARIANT || 'nginx-vts-docker';
const TARGET_HOST = TARGETS[VARIANT];
const BASE_URL = `http://${TARGET_HOST}`;

export const options = {
  scenarios: {
    warmup: {
      executor: 'constant-vus',
      vus: 10,
      duration: '30s',
      startTime: '0s',
      tags: { phase: 'warmup' },
    },
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 50 },
        { duration: '60s', target: 50 },
        { duration: '30s', target: 100 },
        { duration: '60s', target: 100 },
        { duration: '30s', target: 200 },
        { duration: '60s', target: 200 },
        { duration: '30s', target: 0 },
      ],
      startTime: '30s',
      tags: { phase: 'load' },
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    errors: ['rate<0.1'],
  },
};

export default function () {
  const res = http.get(`${BASE_URL}/`, {
    headers: { 'Host': 'benchmark.local' },
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'latency < 500ms': (r) => r.timings.duration < 500,
  });

  errorRate.add(res.status !== 200);
  latencyP95.add(res.timings.duration);
  latencyP99.add(res.timings.duration);
  ttfbP95.add(res.timings.waiting);
  throughputBytes.add(res.body ? res.body.length : 0);

  sleep(0.01);
}

export function handleSummary(data) {
  const variant = VARIANT;
  const summary = {
    variant: variant,
    timestamp: new Date().toISOString(),
    metrics: {
      http_reqs: data.metrics.http_reqs ? data.metrics.http_reqs.values.count : 0,
      http_req_duration_avg: data.metrics.http_req_duration ? data.metrics.http_req_duration.values.avg : 0,
      http_req_duration_p95: data.metrics.http_req_duration ? data.metrics.http_req_duration.values['p(95)'] : 0,
      http_req_duration_p99: data.metrics.http_req_duration ? data.metrics.http_req_duration.values['p(99)'] : 0,
      http_req_duration_max: data.metrics.http_req_duration ? data.metrics.http_req_duration.values.max : 0,
      http_req_waiting_avg: data.metrics.http_req_waiting ? data.metrics.http_req_waiting.values.avg : 0,
      http_req_waiting_p95: data.metrics.http_req_waiting ? data.metrics.http_req_waiting.values['p(95)'] : 0,
      http_req_failed: data.metrics.http_req_failed ? data.metrics.http_req_failed.values.rate : 0,
      errors: data.metrics.errors ? data.metrics.errors.values.rate : 0,
      data_received: data.metrics.data_received ? data.metrics.data_received.values.count : 0,
      data_sent: data.metrics.data_sent ? data.metrics.data_sent.values.count : 0,
      iterations: data.metrics.iterations ? data.metrics.iterations.values.count : 0,
      vus_max: data.metrics.vus_max ? data.metrics.vus_max.values.value : 0,
    },
  };

  const resultFile = `/tmp/k6-summary-${variant}.json`;

  return {
    stdout: JSON.stringify(summary, null, 2),
    [resultFile]: JSON.stringify(summary, null, 2),
  };
}
