import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import DeploymentUnitList from './DeploymentUnitList.vue';
import LiveLogViewer from './LiveLogViewer.vue';
import NodeExecutionTable from './NodeExecutionTable.vue';
import { groupDeploymentUnits } from './deploymentUnits';
import { executionStatusTone } from './jobStatus';

describe('安装任务界面', () => {
  it('父步骤显示数字圆标，子任务保留状态图标与选择行为', async () => {
    const wrapper = mount(DeploymentUnitList, { props: { selectedId: 2, units: groupDeploymentUnits([
      { id: 1, stage_key: 'k8s', stage_name: '部署 Kubernetes', name: '下载镜像', status: 'success' },
      { id: 2, stage_key: 'k8s', stage_name: '部署 Kubernetes', name: '初始化控制平面', status: 'failed' }
    ]) } });
    expect(wrapper.get('.deployment-unit-index').text()).toBe('1');
    expect(wrapper.get('.deployment-unit').classes()).toContain('execution-tone--error');
    expect(wrapper.get('.deployment-unit-index').find('.step-status-icon').exists()).toBe(false);
    expect(wrapper.get('.deployment-unit-status').text()).toBe('失败');
    expect(wrapper.find('.job-stage-index').exists()).toBe(false);
    expect(wrapper.get('[data-testid="job-stage-1"] .step-status-icon').classes()).toContain('execution-tone--success');
    const child = wrapper.get('[data-testid="job-stage-2"]');
    expect(child.attributes('aria-current')).toBe('step');
    expect(child.text()).toContain('失败');
    await child.trigger('click');
    expect(wrapper.emitted('select')).toEqual([[2]]);
    const toggle = wrapper.get('.deployment-unit-toggle');
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('false');
    await wrapper.setProps({ selectable: false });
    expect(wrapper.get('.deployment-unit-index').text()).toBe('1');
  });

  it('只展开当前查看阶段，刷新任务不重新打开其他阶段，选中子任务时定位到所属阶段', async () => {
    const steps = [
      { id: 1, stage_key: 'runtime', stage_name: '部署容器运行时', name: '安装 containerd', status: 'success' },
      { id: 2, stage_key: 'k8s', stage_name: '部署 Kubernetes 集群', name: '初始化集群', status: 'failed' }
    ];
    const wrapper = mount(DeploymentUnitList, { props: { selectedId: 2, units: groupDeploymentUnits(steps) } });
    const expanded = () => wrapper.findAll('.deployment-unit-toggle').map(button => button.attributes('aria-expanded'));
    expect(expanded()).toEqual(['false', 'true']);
    expect(wrapper.get('[data-testid="deployment-unit-runtime"] .deployment-unit-status').text()).toBe('已完成');
    await wrapper.get('[data-testid="deployment-unit-runtime"]').trigger('click');
    expect(expanded()).toEqual(['true', 'false']);
    await wrapper.setProps({ units: groupDeploymentUnits(steps.map(step => ({ ...step }))) });
    expect(expanded()).toEqual(['true', 'false']);
    await wrapper.get('[data-testid="deployment-unit-runtime"]').trigger('click');
    expect(expanded()).toEqual(['false', 'false']);
    await wrapper.setProps({ selectedId: 1 });
    expect(expanded()).toEqual(['true', 'false']);
    await wrapper.setProps({ selectedId: 2 });
    expect(expanded()).toEqual(['false', 'true']);
  });

  it.each([
    ['running', '', 'running'], ['failed', '', 'error'], ['interrupted', '', 'error'],
    ['skipped', 'PREVERIFY_SATISFIED', 'success'], ['skipped', 'JOB_ABORTED', 'pending'], ['pending', '', 'pending']
  ])('展示状态 %s %s 不混淆执行、失败和依赖跳过', (status, reason, tone) => {
    expect(executionStatusTone(status, reason)).toBe(tone);
  });

  it('待安装与依赖阻塞保留独立展示状态，使用同一灰色语义映射时仍可区分', async () => {
    const wrapper = mount(DeploymentUnitList, { props: { units: groupDeploymentUnits([
      { id: 1, stage_key: 'runtime', stage_name: '安装容器运行时', name: '安装 containerd', status: 'pending' },
      { id: 2, stage_key: 'network', stage_name: '部署网络组件', name: '安装 Calico', status: 'skipped', status_reason: 'JOB_ABORTED' }
    ]) } });
    const units = wrapper.findAll('.deployment-unit');
    expect(units.map(unit => unit.attributes('data-state'))).toEqual(['pending', 'blocked']);
    expect(wrapper.get('[data-testid="job-stage-1"]').attributes('data-state')).toBe('pending');
    expect(wrapper.get('[data-testid="job-stage-2"]').attributes('data-state')).toBe('skipped');
    await wrapper.setProps({ units: groupDeploymentUnits([
      { id: 3, stage_key: 'runtime', stage_name: '安装容器运行时', name: '安装 containerd' }
    ]), selectable: false });
    expect(wrapper.get('.deployment-unit').attributes('data-state')).toBe('planned');
  });

  it('只有错误级别或明确错误标记的日志高亮，保留节点和步骤上下文', () => {
    const wrapper = mount(LiveLogViewer, { props: { terminal: true, logs: [
      { id: 1, message: '[INFO] 检查失败重试策略', hostname: 'master-01', stage_name: '初始化' },
      { id: 2, message: '[ERROR] API Server 超时' },
      { id: 3, message: '连接被拒绝', level: 'error' }
    ] } });
    expect(wrapper.findAll('.log-entry--error')).toHaveLength(2);
    expect(wrapper.text()).toContain('[初始化]');
    expect(wrapper.text()).toContain('[master-01]');
    expect(wrapper.get('ol').attributes('tabindex')).toBe('0');
    expect(wrapper.text()).toContain('任务已结束');
  });

  it('没有节点时展示空状态，保留可通过键盘滚动的表格区域', () => {
    const wrapper = mount(NodeExecutionTable, { global: { stubs: { 'el-button': true } } });
    expect(wrapper.get('[role="status"]').text()).toBe('当前步骤暂无节点执行记录。');
    expect(wrapper.get('[role="region"]').attributes('tabindex')).toBe('0');
  });

  it('节点成功展示已完成，失败和运行中使用圆点且保留验证跳过的语义', () => {
    const wrapper = mount(NodeExecutionTable, { props: { nodes: [
      { id: 1, node_id: 1, hostname: 'cp-1', status: 'success' },
      { id: 2, node_id: 2, hostname: 'worker-1', status: 'failed' },
      { id: 3, node_id: 3, hostname: 'worker-2', status: 'running' },
      { id: 4, node_id: 4, hostname: 'worker-3', status: 'skipped', message: 'PREVERIFY_SATISFIED' }
    ] }, global: { stubs: { 'el-button': true } } });
    expect(wrapper.findAll('.node-execution-status').map(status => status.text())).toEqual(['已完成', '失败', '运行中', '已验证并跳过']);
    expect(wrapper.findAll('.node-status-dot')).toHaveLength(4);
    expect(wrapper.find('.step-status-icon').exists()).toBe(false);
  });

  it('节点 IP 和角色来自配置，执行状态与可展开诊断来自任务记录', async () => {
    const wrapper = mount(NodeExecutionTable, { props: {
      nodes: [{ id: 31, node_id: 3, hostname: 'worker-03', status: 'failed', exit_code: 1, message: 'API Server 连接超时' }],
      nodeDetails: [{ id: 3, ip: '192.168.10.13', roles: ['worker'] }]
    }, global: { stubs: { 'el-button': { emits: ['click'], template: '<button @click="$emit(\'click\')"><slot /></button>' } } } });
    expect(wrapper.text()).toContain('192.168.10.13');
    expect(wrapper.text()).toContain('工作节点');
    expect(wrapper.get('details').text()).toContain('退出码 1');
    expect(wrapper.get('details').text()).toContain('API Server 连接超时');
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('select')).toEqual([[3]]);
  });
});
