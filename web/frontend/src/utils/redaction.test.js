import { describe, expect, it } from 'vitest';

import { safeErrorMessage } from './redaction';

describe('safeErrorMessage', () => {
  it.each([
    'password=secret',
    '密码 Kylin123',
    'private_key leaked',
    '私钥内容错误',
    'token=abcdef',
    'client secret exposed'
  ])('拦截敏感错误：%s', (message) => {
    expect(safeErrorMessage(new Error(message))).toBe('服务返回了不可展示的敏感错误，请检查服务端日志。');
  });

  it('保留普通错误说明', () => {
    expect(safeErrorMessage(new Error('服务暂时不可用'))).toBe('服务暂时不可用');
  });
});
