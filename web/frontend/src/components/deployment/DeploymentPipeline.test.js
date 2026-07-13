import { mount, RouterLinkStub } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';

import DeploymentPipeline from './DeploymentPipeline.vue';

const expectedStages = [
  ['cluster-info', '集群信息'],
  ['nodes', '服务器节点'],
  ['settings', '安装配置'],
  ['precheck', '部署预检查'],
  ['install', '执行安装']
];

describe('DeploymentPipeline', () => {
  it('按固定顺序显示五个中文阶段并生成可恢复的阶段路由', () => {
    const wrapper = mount(DeploymentPipeline, {
      props: {
        clusterId: 42,
        activeStage: 'settings'
      },
      global: {
        stubs: { RouterLink: RouterLinkStub }
      }
    });

    const stages = wrapper.findAll('[data-stage-key]');
    expect(stages).toHaveLength(5);
    expect(stages.map((stage) => [stage.attributes('data-stage-key'), stage.get('.pipeline-stage__title').text()]))
      .toEqual(expectedStages);
    expect(stages[2].attributes('aria-current')).toBe('step');

    const links = wrapper.findAllComponents(RouterLinkStub);
    expect(links.map((link) => link.props('to'))).toEqual(
      expectedStages.map(([stage]) => ({
        name: 'cluster-workspace',
        params: { clusterId: '42', stage }
      }))
    );
  });

  it('把英文阶段状态显示为中文文字', () => {
    const wrapper = mount(DeploymentPipeline, {
      props: {
        clusterId: '7',
        activeStage: 'nodes',
        stageStates: {
          'cluster-info': 'completed',
          nodes: 'current',
          settings: 'blocked',
          precheck: 'error',
          install: 'pending'
        }
      },
      global: {
        stubs: { RouterLink: RouterLinkStub }
      }
    });

    expect(wrapper.text()).toContain('已完成');
    expect(wrapper.text()).toContain('进行中');
    expect(wrapper.text()).toContain('暂不可用');
    expect(wrapper.text()).toContain('失败');
    expect(wrapper.text()).toContain('未开始');
  });
});
