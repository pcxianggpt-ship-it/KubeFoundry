import { containsSensitiveError, safeErrorMessage } from '../utils/redaction';

const JSON_HEADERS = {
  'Content-Type': 'application/json'
};

async function request(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      ...(options.body ? JSON_HEADERS : {}),
      ...(options.headers || {})
    }
  });

  const text = await response.text();
  let payload = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (error) {
      payload = text;
    }
  }

  if (!response.ok) {
    const rawMessage =
      payload && (payload.error || payload.message)
        ? payload.error || payload.message
        : `请求失败：${response.status}`;
    const error = new Error(safeErrorMessage({ message: rawMessage }));
    error.status = response.status;
    error.jobId = payload && payload.job_id;
    error.payload = containsSensitiveError(rawMessage) ? null : payload;
    throw error;
  }

  return payload;
}

export function listClusters() {
  return request('/api/clusters');
}

export function getCluster(clusterId) {
  return request(`/api/clusters/${clusterId}`);
}

export function createCluster(data) {
  return request('/api/clusters', {
    method: 'POST',
    body: JSON.stringify(data)
  });
}

export function updateCluster(clusterId, data) {
  return request(`/api/clusters/${clusterId}`, {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

export function listNodes(clusterId) {
  return request(`/api/clusters/${clusterId}/nodes`);
}

export function createNode(clusterId, data) {
  return request(`/api/clusters/${clusterId}/nodes`, {
    method: 'POST',
    body: JSON.stringify(data)
  });
}

export function updateNode(nodeId, data) {
  return request(`/api/nodes/${nodeId}`, {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

export function deleteNode(nodeId) {
  return request(`/api/nodes/${nodeId}`, {
    method: 'DELETE'
  });
}

export function copyNodes(clusterId, nodeIds) {
  return request(`/api/clusters/${clusterId}/nodes/copy`, {
    method: 'POST',
    body: JSON.stringify({ node_ids: nodeIds })
  });
}

export function upsertSshCredentials(clusterId, data) {
  return request(`/api/clusters/${clusterId}/ssh-credentials`, {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

export function getSettings() {
  return request('/api/settings');
}

export function updateSettings(data) {
  return request('/api/settings', {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

export function getClusterSettings(clusterId) {
  return request(`/api/clusters/${clusterId}/settings`);
}

export function updateClusterSettings(clusterId, data) {
  return request(`/api/clusters/${clusterId}/settings`, {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

export function startPrecheck(clusterId) {
  return request(`/api/clusters/${clusterId}/precheck`, {
    method: 'POST'
  });
}

export function startNodeTest(clusterId) {
  return request(`/api/clusters/${clusterId}/node-test`, {
    method: 'POST'
  });
}

export function startInstall(clusterId) {
  return request(`/api/clusters/${clusterId}/install`, {
    method: 'POST',
    body: JSON.stringify({})
  });
}

export function listJobs(clusterId = null) {
  const query = clusterId ? `?cluster_id=${clusterId}` : '';
  return request(`/api/jobs${query}`);
}

export function getInstallPlan() {
  return request('/api/install-plan');
}

export function getClusterConfigYaml(clusterId) {
  return request(`/api/clusters/${clusterId}/config-yaml`);
}

export function importClusterYaml(clusterId, content) {
  return request(`/api/clusters/${clusterId}/import-yaml`, {
    method: 'POST',
    body: JSON.stringify({ content })
  });
}

export function getJob(jobId) {
  return request(`/api/jobs/${jobId}`);
}

export function getJobSteps(jobId) {
  return request(`/api/jobs/${jobId}/steps`);
}

export function getJobLogs(jobId) {
  return request(`/api/jobs/${jobId}/logs`);
}

export function getPrecheckResults(jobId) {
  return request(`/api/jobs/${jobId}/precheck-results`);
}

export function getJobStepNodeLog(itemId) {
  return request(`/api/job-step-nodes/${itemId}/log`);
}

export function getJobConfigYaml(jobId) {
  return request(`/api/jobs/${jobId}/config-yaml`);
}
