/**
 * Dashboard JavaScript - Auto-refresh and interactive features
 */

// Configuration
const REFRESH_INTERVAL = 5000;  // 5 seconds
const API_BASE = '/admin/api';

// State
let refreshTimerId = null;
let isRefreshing = false;

// ============================================================================
// Auto-refresh Dashboard Stats
// ============================================================================

async function refreshDashboardStats() {
    if (isRefreshing) return;
    isRefreshing = true;

    try {
        // Fetch processing status
        const processingRes = await fetch(`${API_BASE}/processing-status`);
        if (processingRes.ok) {
            const data = await processingRes.json();
            updateProcessingSection(data);
        }

        // Fetch system status
        const systemRes = await fetch(`${API_BASE}/system-status`);
        if (systemRes.ok) {
            const data = await systemRes.json();
            updateSystemStats(data);
        }

    } catch (error) {
        console.error('Failed to refresh dashboard:', error);
    } finally {
        isRefreshing = false;
    }
}

function updateProcessingSection(data) {
    const countEl = document.getElementById('processing-count');
    if (countEl) {
        countEl.textContent = data.active_jobs.length;
    }

    // Update active jobs list if exists
    const jobsContainer = document.getElementById('active-jobs-list');
    if (jobsContainer && data.active_jobs.length > 0) {
        let html = '';
        data.active_jobs.forEach(job => {
            html += `
                <div class="flex items-center justify-between p-3 bg-gray-700 rounded-lg">
                    <div>
                        <div class="font-medium">${escapeHtml(job.name)}</div>
                        <div class="text-sm text-gray-400">${job.stage}</div>
                    </div>
                    <div class="text-right">
                        <div class="text-lg font-bold">${job.progress}%</div>
                        <div class="w-20 bg-gray-600 rounded-full h-2 mt-1">
                            <div class="bg-blue-500 h-2 rounded-full" style="width: ${job.progress}%"></div>
                        </div>
                    </div>
                </div>
            `;
        });
        jobsContainer.innerHTML = html;
    }
}

function updateSystemStats(data) {
    // Update CPU
    const cpuEl = document.getElementById('cpu-usage');
    if (cpuEl && data.system) {
        cpuEl.textContent = `${data.system.cpu_percent}%`;
    }

    // Update Memory
    const memEl = document.getElementById('memory-usage');
    if (memEl && data.system) {
        memEl.textContent = `${data.system.memory_percent}%`;
    }

    // Update GPU info
    if (data.gpus && data.gpus.length > 0) {
        data.gpus.forEach((gpu, index) => {
            const gpuNameEl = document.getElementById(`gpu-${index}-name`);
            const gpuMemEl = document.getElementById(`gpu-${index}-memory`);
            const gpuUtilEl = document.getElementById(`gpu-${index}-util`);

            if (gpuNameEl) gpuNameEl.textContent = gpu.name;
            if (gpuMemEl) gpuMemEl.textContent = `${gpu.memory_used}/${gpu.memory_total} MB`;
            if (gpuUtilEl) gpuUtilEl.textContent = `${gpu.utilization}%`;
        });
    }
}

// ============================================================================
// Log Viewer
// ============================================================================

async function loadLogs(options = {}) {
    const {
        endpoint = '/admin/api/logs/recent',
        limit = 100,
        level = null,
        category = null,
        containerId = 'logs-container'
    } = options;

    const container = document.getElementById(containerId);
    if (!container) return;

    try {
        let url = `${endpoint}?limit=${limit}`;
        if (level) url += `&level=${level}`;
        if (category) url += `&category=${category}`;

        const res = await fetch(url);
        if (!res.ok) throw new Error('Failed to fetch logs');

        const data = await res.json();
        renderLogs(container, data.logs || data);

        // Update stats if present
        if (data.stats) {
            updateLogStats(data.stats);
        }

    } catch (error) {
        container.innerHTML = `<div class="text-red-500">Error loading logs: ${error.message}</div>`;
    }
}

function renderLogs(container, logs) {
    if (!logs || logs.length === 0) {
        container.innerHTML = '<div class="text-gray-500 p-4">No logs found</div>';
        return;
    }

    const levelColors = {
        'debug': 'text-gray-400',
        'info': 'text-blue-400',
        'warning': 'text-yellow-400',
        'error': 'text-red-400'
    };

    let html = '<div class="space-y-1 font-mono text-sm">';

    logs.forEach(log => {
        const levelClass = levelColors[log.level] || 'text-gray-400';
        const timestamp = log.timestamp ? new Date(log.timestamp).toLocaleTimeString() : '';

        html += `
            <div class="flex gap-2 p-2 hover:bg-gray-700 rounded">
                <span class="text-gray-500 shrink-0">${timestamp}</span>
                <span class="${levelClass} shrink-0 w-16">[${log.level.toUpperCase()}]</span>
                <span class="text-purple-400 shrink-0">${log.category || 'system'}</span>
                <span class="text-gray-200">${escapeHtml(log.message)}</span>
                ${log.scan_id ? `<span class="text-gray-500 text-xs">(scan: ${log.scan_id.substring(0, 8)})</span>` : ''}
            </div>
        `;
    });

    html += '</div>';
    container.innerHTML = html;
}

function updateLogStats(stats) {
    const totalEl = document.getElementById('log-stats-total');
    const errorsEl = document.getElementById('log-stats-errors');

    if (totalEl) totalEl.textContent = stats.total_logs || 0;
    if (errorsEl) errorsEl.textContent = stats.total_errors || 0;
}

// ============================================================================
// Scan Actions
// ============================================================================

async function deleteScan(scanId, name) {
    if (!confirm(`Are you sure you want to delete "${name}"?`)) return;

    try {
        const res = await fetch(`${API_BASE}/scans/${scanId}`, { method: 'DELETE' });
        if (res.ok) {
            // Remove from DOM or reload
            const row = document.querySelector(`[data-scan-id="${scanId}"]`);
            if (row) {
                row.remove();
            } else {
                window.location.reload();
            }
        } else {
            alert('Failed to delete scan');
        }
    } catch (error) {
        alert(`Error: ${error.message}`);
    }
}

async function cancelProcessing(scanId) {
    if (!confirm('Cancel processing for this scan?')) return;

    try {
        const res = await fetch(`${API_BASE}/scans/${scanId}/cancel`, { method: 'POST' });
        if (res.ok) {
            window.location.reload();
        } else {
            alert('Failed to cancel processing');
        }
    } catch (error) {
        alert(`Error: ${error.message}`);
    }
}

async function removeFromQueue(scanId) {
    try {
        const res = await fetch(`${API_BASE}/queue/${scanId}`, { method: 'DELETE' });
        if (res.ok) {
            window.location.reload();
        } else {
            alert('Failed to remove from queue');
        }
    } catch (error) {
        alert(`Error: ${error.message}`);
    }
}

// ============================================================================
// 3D Viewer
// ============================================================================

function open3DViewer(scanId) {
    const viewerUrl = `/api/v1/debug/scans/${scanId}/viewer`;
    window.open(viewerUrl, '_blank', 'width=1024,height=768');
}

function loadPointCloudPreview(scanId, containerId) {
    // This would integrate with Three.js for point cloud rendering
    // For now, just fetch the data
    fetch(`/api/v1/debug/scans/${scanId}/pointcloud/preview?max_points=10000`)
        .then(res => res.json())
        .then(data => {
            console.log(`Loaded ${data.point_count} points for preview`);
            // TODO: Integrate with Three.js
        })
        .catch(err => console.error('Failed to load point cloud:', err));
}

// ============================================================================
// Utilities
// ============================================================================

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function formatDuration(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);

    if (h > 0) return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
    return `${m}:${s.toString().padStart(2, '0')}`;
}

// ============================================================================
// Initialization
// ============================================================================

function startAutoRefresh() {
    if (refreshTimerId) return;

    // Initial refresh
    refreshDashboardStats();

    // Set up interval
    refreshTimerId = setInterval(refreshDashboardStats, REFRESH_INTERVAL);

    console.log('Auto-refresh started');
}

function stopAutoRefresh() {
    if (refreshTimerId) {
        clearInterval(refreshTimerId);
        refreshTimerId = null;
        console.log('Auto-refresh stopped');
    }
}

// Auto-start on dashboard page
document.addEventListener('DOMContentLoaded', () => {
    // Check if we're on a page that needs auto-refresh
    const dashboardEl = document.getElementById('dashboard-content');
    const systemEl = document.getElementById('system-content');
    const processingEl = document.getElementById('processing-content');

    if (dashboardEl || systemEl || processingEl) {
        startAutoRefresh();
    }

    // Check for log viewer
    const logsContainer = document.getElementById('logs-container');
    if (logsContainer) {
        loadLogs();
    }
});

// Stop refresh when page is hidden
document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
        stopAutoRefresh();
    } else {
        startAutoRefresh();
    }
});
