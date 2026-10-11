import { describe, expect, it } from 'vitest';
import { redisPasswordError } from './redisConfig';

describe('Redis password configuration', () => {
  it('保留空值和含特殊字符的合法密码，拒绝控制字符和超长输入', () => {
    for (const password of ['', 'x', "test-only- 中文 '$;&", 'x'.repeat(256)]) {
      expect(redisPasswordError({ password })).toBe('');
    }
    for (const password of ['   ', 'test-only\nvalue', 'test-only\u0085value', 'x'.repeat(257), 123]) {
      expect(redisPasswordError({ password })).not.toBe('');
    }
  });
});
