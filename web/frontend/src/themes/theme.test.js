import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DEFAULT_THEME, initializeTheme, setTheme, theme, THEME_STORAGE_KEY } from './theme';

describe('界面主题偏好', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    localStorage.clear();
    initializeTheme();
  });

  it('首次访问使用 Apple 版，根元素同步主题', () => {
    expect(theme.value).toBe(DEFAULT_THEME);
    expect(document.documentElement.dataset.kfTheme).toBe('apple');
  });

  it('切换后保存选择，重新初始化恢复经典版', () => {
    setTheme('classic');
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe('classic');
    expect(document.documentElement.dataset.kfTheme).toBe('classic');
    initializeTheme();
    expect(theme.value).toBe('classic');
  });

  it('未知存储值回退默认版，拒绝非法切换值', () => {
    localStorage.setItem(THEME_STORAGE_KEY, 'unknown');
    initializeTheme();
    expect(theme.value).toBe('apple');
    setTheme('classic');
    setTheme('unknown');
    expect(theme.value).toBe('classic');
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe('classic');
  });

  it('存储被禁用时仍可初始化并即时切换', () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('denied'); });
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('denied'); });
    expect(initializeTheme).not.toThrow();
    expect(() => setTheme('classic')).not.toThrow();
    expect(document.documentElement.dataset.kfTheme).toBe('classic');
  });
});
