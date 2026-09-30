import { describe, expect, it } from 'vitest';

import { minioConfigErrors, normalizeMinioConfig } from './minioConfig';

describe('MinIO resource configuration', () => {
  it('提供与离线 Tenant 一致的默认值', () => {
    expect(normalizeMinioConfig()).toEqual({
      minio_pvc_size: '10Gi',
      minio_cpu_request: '250m',
      minio_cpu_limit: '2',
      minio_memory_request: '512Mi',
      minio_memory_limit: '4Gi'
    });
    expect(minioConfigErrors()).toEqual({});
  });

  it('拒绝非法、零值以及 request 大于 limit', () => {
    expect(minioConfigErrors({ minio_pvc_size: '0Gi' })).toHaveProperty('minio_pvc_size');
    expect(minioConfigErrors({ minio_cpu_request: '3', minio_cpu_limit: '2' }))
      .toHaveProperty('minio_cpu_limit');
    expect(minioConfigErrors({ minio_memory_request: 'bad' }))
      .toHaveProperty('minio_memory_request');
  });
});
