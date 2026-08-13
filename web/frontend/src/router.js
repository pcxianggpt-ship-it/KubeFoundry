import { createRouter, createWebHistory } from 'vue-router';

import AppShell from './layouts/AppShell.vue';
import ClusterListView from './views/ClusterListView.vue';
import ClusterWorkspaceView from './views/ClusterWorkspaceView.vue';
import InstallOverviewView from './views/InstallOverviewView.vue';
import InstallConfirmView from './views/InstallConfirmView.vue';
import JobExecutionView from './views/JobExecutionView.vue';
import PrecheckView from './views/PrecheckView.vue';
import ResetConfirmView from './views/ResetConfirmView.vue';

const STAGE_PATTERN = 'cluster-info|nodes|components|precheck';

export const routes = [
  {
    path: '/',
    component: AppShell,
    children: [
      {
        path: '',
        redirect: { name: 'cluster-config-list' }
      },
      {
        path: 'cluster-config',
        name: 'cluster-config-list',
        component: ClusterListView,
        props: { mode: 'config' }
      },
      {
        path: `cluster-config/:clusterId/:stage(${STAGE_PATTERN})`,
        name: 'cluster-config-workspace',
        component: ClusterWorkspaceView
      },
      {
        path: 'cluster-install',
        name: 'cluster-install-list',
        component: ClusterListView,
        props: { mode: 'install' }
      },
      {
        path: 'cluster-install/:clusterId',
        redirect: (to) => ({ name: 'install-overview', params: { clusterId: to.params.clusterId } })
      },
      {
        path: 'cluster-install/:clusterId/overview',
        name: 'install-overview',
        component: InstallOverviewView
      },
      {
        path: 'cluster-install/:clusterId/precheck',
        name: 'install-precheck',
        component: PrecheckView,
        props: (route) => ({ clusterId: route.params.clusterId })
      },
      {
        path: 'cluster-install/:clusterId/confirm',
        name: 'install-confirm',
        component: InstallConfirmView
      },
      {
        path: 'cluster-install/:clusterId/reset',
        name: 'reset-confirm',
        component: ResetConfirmView
      },
      {
        path: 'cluster-install/:clusterId/jobs/:jobId',
        name: 'cluster-job-execution',
        component: JobExecutionView
      },
      {
        path: 'clusters/:clusterId',
        redirect: (to) => ({
          name: 'cluster-config-workspace',
          params: { clusterId: to.params.clusterId, stage: 'cluster-info' }
        })
      },
      {
        path: `clusters/:clusterId/:stage(${STAGE_PATTERN})`,
        redirect: (to) => ({
          name: 'cluster-config-workspace',
          params: { clusterId: to.params.clusterId, stage: to.params.stage }
        })
      },
      {
        path: 'clusters/:clusterId/install',
        redirect: (to) => ({ name: 'install-overview', params: { clusterId: to.params.clusterId } })
      },
      {
        path: 'clusters/:clusterId/install/confirm',
        redirect: (to) => ({ name: 'install-confirm', params: { clusterId: to.params.clusterId } })
      },
      {
        path: 'jobs/:jobId/execution',
        name: 'job-execution',
        component: JobExecutionView
      }
    ]
  },
  {
    path: '/:pathMatch(.*)*',
    redirect: '/'
  }
];

export function createAppRouter(history = createWebHistory(import.meta.env.BASE_URL)) {
  return createRouter({
    history,
    routes
  });
}

export default createAppRouter();
