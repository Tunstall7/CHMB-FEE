function [constraintViolation, allocation] = ...
    hydroclimaticCarryingCapacityConstraint(decisionShares, config)
%HYDROCLIMATICCARRYINGCAPACITYCONSTRAINT Constraint 2 in the Borg code.
%
% The precomputed Scenario-B hydroclimatic (water-energy/Budyko) limits
% define the maximum forest proportion in each of ten subbasins:
%
%   forest_fraction_i <= forest_cap_i,    i = 1,...,10.
%
% The global forest target must also fit within the total area-weighted
% forest capacity. The candidate is spatially allocated exactly as in the
% original allocateLandUse.m: bounded forest allocation first, then RAS
% allocation of the remaining five land-use classes.
%
% INPUTS
%   decisionShares  Six nonnegative basin-wide land-use shares, ordered:
%                   Cropland, Forest, Grassland, Water, Impervious, BareLand.
%                   They are normalized to sum to one.
%   config          Structure returned by getLandUseConstraintConfig.m.
%                   If omitted, that function is called automatically.
%                   Required fields: areaKm2 (10x1), totalAreaKm2,
%                   forestCap (10x1), baselineAreaKm2 (10x6),
%                   areaToleranceKm2, fractionTolerance,
%                   rasMaximumIterations.
%
% OUTPUTS
%   constraintViolation  Borg constraint 2 (zero is feasible).
%   allocation           Spatial allocation and diagnostics.
%
% EXAMPLE
%   cfg = getLandUseConstraintConfig();
%   [g2, info] = hydroclimaticCarryingCapacityConstraint( ...
%       [0.20 0.40 0.30 0.02 0.04 0.04], cfg);
%
% IMPORTANT
%   This function enforces the PRECOMPUTED forest caps. The caps themselves
%   are supplied by getLandUseConstraintConfig.m from the supporting Excel
%   workbook; this function does not derive them from P, PET, or AET.
%
% Adapted from allocateLandUse.m and the constraint assignment in
% threeObjectiveFunction.m. No HEC-HMS simulation is launched here.

    if nargin < 2 || isempty(config)
        config = getLandUseConstraintConfig();
    end
    decisionShares = decisionShares(:)';
    if numel(decisionShares) ~= 6 || any(~isfinite(decisionShares)) || ...
            any(decisionShares < 0) || sum(decisionShares) <= 0
        error('LUCC:InvalidDecisionShares', ...
            'Expected six finite nonnegative decision values with positive sum.');
    end
    x = decisionShares / sum(decisionShares);

    targetAreaByLandUse = x * config.totalAreaKm2;
    forestTarget = targetAreaByLandUse(2);
    forestCapacity = config.areaKm2 .* config.forestCap;
    forestGlobalExcessKm2 = max(0, forestTarget - sum(forestCapacity));

    allocation = emptyAllocation(config, x, targetAreaByLandUse);
    allocation.forestGlobalExcessKm2 = forestGlobalExcessKm2;
    allocation.forestConstraintViolation = ...
        forestGlobalExcessKm2 / config.totalAreaKm2;
    if forestGlobalExcessKm2 > config.areaToleranceKm2
        allocation.status = 'ForestTargetExceedsWaterEnergyCapacity';
        constraintViolation = allocation.forestConstraintViolation;
        return
    end

    currentForestArea = config.baselineAreaKm2(:, 2);
    forestArea = boundedProportionalAllocation(forestTarget, ...
        currentForestArea, forestCapacity, config.areaToleranceKm2);
    remainingArea = config.areaKm2 - forestArea;

    nonForestColumns = [1, 3, 4, 5, 6];
    nonForestTargets = targetAreaByLandUse(nonForestColumns);
    nonForestPreference = config.baselineAreaKm2(:, nonForestColumns);
    [nonForestArea, rasConverged] = rasTransport(nonForestPreference, ...
        remainingArea, nonForestTargets, config.areaToleranceKm2, ...
        config.rasMaximumIterations);
    if ~rasConverged
        allocation.status = 'SpatialAllocationDidNotConverge';
        allocation.forestConstraintViolation = 1;
        constraintViolation = 1;
        return
    end

    nSubbasins = numel(config.areaKm2);
    areaKm2 = zeros(nSubbasins, 6);
    areaKm2(:, 2) = forestArea;
    areaKm2(:, nonForestColumns) = nonForestArea;
    fractions = areaKm2 ./ config.areaKm2;

    rowAreaErrorKm2 = sum(areaKm2, 2) - config.areaKm2;
    columnAreaErrorKm2 = sum(areaKm2, 1) - targetAreaByLandUse;
    forestExcessFraction = max(0, fractions(:, 2) - config.forestCap);
    maxAreaBalanceErrorFraction = max(abs(sum(fractions, 2) - 1));

    allocation.areaKm2 = areaKm2;
    allocation.fractions = fractions;
    allocation.rowAreaErrorKm2 = rowAreaErrorKm2;
    allocation.columnAreaErrorKm2 = columnAreaErrorKm2;
    allocation.forestExcessFraction = forestExcessFraction;
    allocation.maxForestCapExcessFraction = max(forestExcessFraction);
    allocation.maxAreaBalanceErrorFraction = maxAreaBalanceErrorFraction;
    allocation.forestConstraintViolation = ...
        max(allocation.forestConstraintViolation, ...
        allocation.maxForestCapExcessFraction);

    allocation.isFeasible = ...
        all(areaKm2 >= -config.areaToleranceKm2, 'all') && ...
        max(abs(rowAreaErrorKm2)) <= config.areaToleranceKm2 && ...
        max(abs(columnAreaErrorKm2)) <= config.areaToleranceKm2 && ...
        allocation.maxForestCapExcessFraction <= config.fractionTolerance && ...
        maxAreaBalanceErrorFraction <= config.fractionTolerance && ...
        all(fractions >= -config.fractionTolerance, 'all') && ...
        all(fractions <= 1 + config.fractionTolerance, 'all');
    if allocation.isFeasible
        allocation.status = 'Feasible';
        allocation.forestConstraintViolation = 0;
    else
        allocation.status = 'SpatialAllocationConstraintFailed';
        allocation.forestConstraintViolation = max( ...
            allocation.forestConstraintViolation, ...
            maxAreaBalanceErrorFraction);
    end

    constraintViolation = allocation.forestConstraintViolation;
end

function allocation = emptyAllocation(config, x, targetAreaByLandUse)
    nSubbasins = numel(config.areaKm2);
    allocation = struct();
    allocation.isFeasible = false;
    allocation.status = 'NotAllocated';
    allocation.x = x;
    allocation.targetAreaByLandUseKm2 = targetAreaByLandUse;
    allocation.areaKm2 = NaN(nSubbasins, 6);
    allocation.fractions = NaN(nSubbasins, 6);
    allocation.rowAreaErrorKm2 = NaN(nSubbasins, 1);
    allocation.columnAreaErrorKm2 = NaN(1, 6);
    allocation.forestGlobalExcessKm2 = NaN;
    allocation.forestConstraintViolation = NaN;
    allocation.forestExcessFraction = NaN(nSubbasins, 1);
    allocation.maxForestCapExcessFraction = NaN;
    allocation.maxAreaBalanceErrorFraction = NaN;
    allocation.forestCap = config.forestCap;
end

function allocated = boundedProportionalAllocation(target, weights, caps, tolerance)
    if target < -tolerance || target > sum(caps) + tolerance
        error('LUCC:BoundedAllocationInfeasible', ...
            'The forest target is outside the available capacity.');
    end
    target = min(max(target, 0), sum(caps));
    if target <= tolerance
        allocated = zeros(size(caps));
        return
    end
    if abs(target - sum(weights)) <= tolerance && all(weights <= caps + tolerance)
        allocated = weights;
        return
    end

    weights = max(weights, 0);
    if sum(weights) <= 0
        weights = caps;
    end
    positiveCaps = caps > tolerance;
    weights(positiveCaps & weights <= 0) = ...
        max(mean(weights(weights > 0)), 1) * 1e-9;
    weights(~positiveCaps) = 0;

    lowerScale = 0;
    upperScale = max(1, target / max(sum(weights), eps));
    while sum(min(caps, upperScale * weights)) < target - tolerance
        upperScale = upperScale * 2;
        if upperScale > 1e20
            error('LUCC:BoundedAllocationFailed', ...
                'Could not bracket the bounded forest allocation.');
        end
    end
    for iteration = 1:200
        middleScale = (lowerScale + upperScale) / 2;
        candidate = min(caps, middleScale * weights);
        if sum(candidate) < target
            lowerScale = middleScale;
        else
            upperScale = middleScale;
        end
    end
    allocated = min(caps, upperScale * weights);
    residual = target - sum(allocated);
    if abs(residual) > tolerance
        available = caps - allocated;
        if residual > 0
            index = find(available > tolerance, 1, 'first');
        else
            index = find(allocated > tolerance, 1, 'first');
        end
        if isempty(index)
            error('LUCC:BoundedAllocationResidual', ...
                'Could not remove the final forest-allocation residual.');
        end
        allocated(index) = allocated(index) + residual;
    end
end

function [matrix, converged] = rasTransport(preference, rowTargets, ...
        columnTargets, tolerance, maximumIterations)
    matrix = zeros(size(preference));
    rowActive = rowTargets > tolerance;
    columnActive = columnTargets > tolerance;
    if ~any(rowActive) && ~any(columnActive)
        converged = true;
        return
    end
    if abs(sum(rowTargets) - sum(columnTargets)) > tolerance
        error('LUCC:TransportationMarginsMismatch', ...
            'Row and column targets differ by %.12g km^2.', ...
            sum(rowTargets) - sum(columnTargets));
    end
    if any(rowActive) ~= any(columnActive)
        converged = false;
        return
    end

    rowMarginal = rowTargets(rowActive);
    columnMarginal = columnTargets(columnActive);
    seed = max(preference(rowActive, columnActive), 0);
    independentSeed = rowMarginal * columnMarginal / sum(rowMarginal);
    seed = seed + max(independentSeed, 1) * 1e-12;

    converged = false;
    for iteration = 1:maximumIterations
        seed = seed .* (rowMarginal ./ sum(seed, 2));
        seed = seed .* (columnMarginal ./ sum(seed, 1));
        rowError = max(abs(sum(seed, 2) - rowMarginal));
        columnError = max(abs(sum(seed, 1) - columnMarginal));
        if max(rowError, columnError) <= tolerance
            converged = true;
            break
        end
    end
    matrix(rowActive, columnActive) = seed;
end
