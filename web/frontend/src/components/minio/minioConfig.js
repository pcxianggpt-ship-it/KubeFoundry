export const MINIO_DEFAULTS = Object.freeze({
  minio_pvc_size: '10Gi',
  minio_cpu_request: '250m',
  minio_cpu_limit: '2',
  minio_memory_request: '512Mi',
  minio_memory_limit: '4Gi'
});

export function normalizeMinioConfig(config = {}) {
  return { ...MINIO_DEFAULTS, ...config };
}

export function minioConfigErrors(config = {}) {
  const values = normalizeMinioConfig(config);
  const errors = {};
  const pvc = parseBytes(values.minio_pvc_size);
  const cpuRequest = parseCpu(values.minio_cpu_request);
  const cpuLimit = parseCpu(values.minio_cpu_limit);
  const memoryRequest = parseBytes(values.minio_memory_request);
  const memoryLimit = parseBytes(values.minio_memory_limit);

  if (!(pvc > 0)) errors.minio_pvc_size = '请输入大于 0 的容量，例如 10Gi。';
  if (!(cpuRequest > 0)) errors.minio_cpu_request = '请输入正 CPU Quantity，例如 250m。';
  if (!(cpuLimit > 0)) errors.minio_cpu_limit = '请输入正 CPU Quantity，例如 2。';
  if (!(memoryRequest > 0)) errors.minio_memory_request = '请输入正容量，例如 512Mi。';
  if (!(memoryLimit > 0)) errors.minio_memory_limit = '请输入正容量，例如 4Gi。';
  if (cpuRequest > 0 && cpuLimit > 0 && cpuRequest > cpuLimit) {
    errors.minio_cpu_limit = 'CPU limit 不能小于 request。';
  }
  if (memoryRequest > 0 && memoryLimit > 0 && memoryRequest > memoryLimit) {
    errors.minio_memory_limit = '内存 limit 不能小于 request。';
  }
  return errors;
}

function parseCpu(value) {
  if (typeof value !== 'string') return NaN;
  const match = value.trim().match(/^([0-9]+(?:\.[0-9]+)?)(m)?$/);
  if (!match) return NaN;
  const amount = Number(match[1]);
  return match[2] ? amount / 1000 : amount;
}

function parseBytes(value) {
  if (typeof value !== 'string') return NaN;
  const match = value.trim().match(/^([0-9]+(?:\.[0-9]+)?)(Ki|Mi|Gi|Ti|Pi|Ei)?$/);
  if (!match) return NaN;
  const powers = { Ki: 1, Mi: 2, Gi: 3, Ti: 4, Pi: 5, Ei: 6 };
  return Number(match[1]) * (match[2] ? 1024 ** powers[match[2]] : 1);
}
