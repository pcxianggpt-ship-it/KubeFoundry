import { describe, expect, it } from 'vitest';
import { redisPasswordError } from './redisConfig';

describe('Redis password configuration', () => {
  it('要求未配置的密码必填，支持合法特殊字符，拒绝控制字符和超长输入', () => {
    for (const password of ['x', "test-only- 中文 '$;&", 'x'.repeat(256)]) {
      expect(redisPasswordError({ password })).toBe('');
    }
    for (const password of ['', '   ', 'test-only\nvalue', 'test-only\u0085value', 'x'.repeat(257), 123]) {
      expect(redisPasswordError({ password })).not.toBe('');
    }
    expect(redisPasswordError({})).not.toBe('');
    expect(redisPasswordError({ has_password: true, password: '' })).toBe('');
  });
});
