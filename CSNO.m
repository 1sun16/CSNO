%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%  
%  Cicada Soundscape Navigation Optimizer (CSNO) source codes 
%  
%  Developed in:	MATLAB (R2024a)
%  
%  Mechanism:       Triple Acoustic Guidance, Interactive Memory, 
%                   and Lifecycle-aware Acceptance.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [bestx, bestf, ConvergenceCurve] = CSNO(fobj, dim, lb, ub, options)
%% 1. 解析参数 (从 options 提取)
if isfield(options, 'PopulationSize')
    N = options.PopulationSize;
elseif isfield(options, 'PopSize')
    N = options.PopSize;
else
    error('CSNO:MissingPopulationSize', 'options.PopulationSize is required.');
end

if isfield(options, 'MaxIterations')
    T = options.MaxIterations;
elseif isfield(options, 'MaxFEs')
    T = max(1, ceil(options.MaxFEs / N));
else
    error('CSNO:MissingBudget', 'options.MaxIterations is required.');
end

% --- 核心 CSNO 参数 ---
base_neighbors = min(7, N - 1);         % 此时的 N 是正常的数字了
ConvergenceCurve = zeros(1, T);

% --- 初始化种群 ---
positions = lb + (ub - lb) .* rand(N, dim);
fitness = zeros(N, 1);
acoustic_memory = zeros(N, base_neighbors); % Acoustic Interactive Memory (AIM)

% Initial evaluation
for i = 1:N
    fitness(i) = fobj(positions(i, :)); % 统一使用 fobj
end
[bestf, best_idx] = min(fitness);
bestx = positions(best_idx, :);
neighbor_indices = [];

%% 2. Main Loop (Summer Lifecycle)
for t = 1 : T
    progress = t / T; % Temporal progress of the summer season
    
    % --- Acoustic Neighbor Selection ---
    if mod(t, 20) == 1 || isempty(neighbor_indices)
        neighbor_indices = select_neighbors(positions, fitness, base_neighbors);
    end
    
    % --- Acoustic Interactive Memory (AIM) Update ---
    acoustic_memory = update_memory(positions, fitness, acoustic_memory, neighbor_indices, progress);
    
    % --- Triple Acoustic Guidance Update ---
    new_positions = apply_triple_guidance(positions, bestx, acoustic_memory, ...
                                          neighbor_indices, lb, ub, progress, dim);
    
    % --- Lifecycle-aware Acceptance (LA) ---
    [positions, fitness] = evaluate_lifecycle(positions, new_positions, fitness, fobj, progress);
    
    % Update Global Best
    [current_best, best_idx] = min(fitness);
    if current_best < bestf
        bestf = current_best;
        bestx = positions(best_idx, :);
    end
    
    % Record convergence curve
    ConvergenceCurve(t) = bestf;
end
end

%% ================== Helper Functions ==================
function indices = select_neighbors(positions, fitness, k_neighbors)
    nPop = size(positions, 1);
    indices = zeros(nPop, k_neighbors);
    [~, sorted_idx] = sort(fitness);
    
    for i = 1:nPop
        candidates = sorted_idx(1:min(nPop, 2*k_neighbors));
        candidates(candidates == i) = []; 
        
        if length(candidates) >= k_neighbors
            selected = candidates(1:k_neighbors);
        else
            all_indices = 1:nPop;
            all_indices(all_indices == i) = [];
            additional = setdiff(all_indices, candidates);
            selected = [candidates, additional(1:k_neighbors-length(candidates))];
        end
        indices(i, :) = selected(1:k_neighbors);
    end
end

function memory = update_memory(pos, fit, memory, neighbor_idx, progress)
    nPop = size(pos, 1);
    alpha = 0.7 - 0.3 * progress; 
    beta = 0.3 + 0.2 * progress;  
    
    for i = 1:nPop
        neighbors = neighbor_idx(i, :);
        for k = 1:length(neighbors)
            j = neighbors(k);
            if j > 0 && i ~= j
                dist = norm(pos(i, :) - pos(j, :));
                fit_gap = fit(i) - fit(j);
                
                attenuation = exp(-0.05 * dist) / (dist + 1);
                interaction_prob = attenuation * (fit_gap / (abs(fit(i)) + eps));
                
                if fit_gap > 0
                    memory(i, k) = alpha * memory(i, k) + beta * interaction_prob;
                else
                    memory(i, k) = memory(i, k) * (0.9 - 0.1 * progress);
                end
            end
        end
    end
end

function new_pos = apply_triple_guidance(pos, best_pos, memory, neighbor_idx, lb, ub, progress, dim)
    nPop = size(pos, 1);
    new_pos = pos;
    
    w_explore = (0.40 - 0.30 * progress);
    w_local   = (0.30 - 0.10 * progress);
    w_global  = (0.30 + 0.40 * progress);
    
    total_w = w_explore + w_local + w_global;
    w_explore = w_explore / total_w;
    w_local = w_local / total_w;
    w_global = w_global / total_w;
    for i = 1:nPop
        neighbors = neighbor_idx(i, :);
        weights = memory(i, :);
        
        local_sum = sum(weights);
        if local_sum > 0
            weighted_pos = zeros(1, dim);
            for k = 1:length(neighbors)
                j = neighbors(k);
                weighted_pos = weighted_pos + weights(k) * pos(j, :);
            end
            local_guidance = (weighted_pos / local_sum) - pos(i, :);
        else
            local_guidance = zeros(1, dim);
        end
        
        global_guidance = best_pos - pos(i, :);
        exploration = (1 - progress) * (ub - lb) .* (rand(1, dim) - 0.5);
        
        new_pos(i, :) = pos(i, :) + w_local * local_guidance + ...
                        w_global * global_guidance + w_explore * exploration;
        
        new_pos(i, :) = max(new_pos(i, :), lb);
        new_pos(i, :) = min(new_pos(i, :), ub);
    end
end

function [pos, fit] = evaluate_lifecycle(pos, new_pos, fit, fobj, progress)
    nPop = size(pos, 1);
    tolerance = 0.05 * progress; 
    
    for i = 1:nPop
        new_fit = fobj(new_pos(i, :));
        if new_fit < fit(i) * (1 + tolerance)
            pos(i, :) = new_pos(i, :);
            fit(i) = new_fit;
        end
    end
end