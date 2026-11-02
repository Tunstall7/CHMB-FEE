function [constraintViolationNormalized, diagnostics] = ...
    waterRetentionCapacityConstraint(candidateRunoffVolume, ...
    baselineRunoffVolume, commonPrecipitationVolume)
%WATERRETENTIONCAPACITYCONSTRAINT Constraint 1 in the supplied Borg code.
%
% The same rainfall event and contributing area are used for the candidate
% and baseline HEC-HMS simulations (J11 outlet runoff volumes in m^3).
%
%   R_candidate = 1 - V_candidate / V_precipitation
%   R_baseline  = 1 - V_baseline  / V_precipitation
%
% Requiring R_candidate >= R_baseline is equivalent to requiring
% V_candidate <= V_baseline. Borg expects a nonpositive constraint for a
% feasible solution; here it receives a nonnegative violation equal to 0
% when feasible:
%
%   g1 = max(0, V_candidate - V_baseline) / max(V_baseline, 1)
%
% INPUTS
%   candidateRunoffVolume   Candidate integrated runoff volume (m^3).
%   baselineRunoffVolume    Baseline integrated runoff volume (m^3).
%   commonPrecipitationVolume (optional) Shared precipitation volume (m^3)
%       for displaying the equivalent water-retention rates.
%
% OUTPUTS
%   constraintViolationNormalized   Borg constraint 1 (feasible if zero).
%   diagnostics                     Raw volumes, residuals, and rates.
%
% EXAMPLE
%   [g1, info] = waterRetentionCapacityConstraint(300, 400, 1000);
%   % g1 = 0; info.candidateRetentionRate = 0.7
%
% Extracted from calculateWaterRetentionConstraint.m and its normalization
% in threeObjectiveFunction.m. No HEC-HMS simulation is launched here.

    validateattributes(candidateRunoffVolume, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'}, mfilename, ...
        'candidateRunoffVolume');
    validateattributes(baselineRunoffVolume, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'}, mfilename, ...
        'baselineRunoffVolume');

    signedResidualVolume = candidateRunoffVolume - baselineRunoffVolume;
    violationVolume = max(0, signedResidualVolume);
    constraintViolationNormalized = violationVolume / ...
        max(baselineRunoffVolume, 1);

    diagnostics = struct();
    diagnostics.candidateRunoffVolume = candidateRunoffVolume;
    diagnostics.baselineRunoffVolume = baselineRunoffVolume;
    diagnostics.signedResidualVolume = signedResidualVolume;
    diagnostics.violationVolume = violationVolume;
    diagnostics.candidateRetentionRate = NaN;
    diagnostics.baselineRetentionRate = NaN;
    diagnostics.signedResidualRate = NaN;
    diagnostics.violationRate = NaN;
    diagnostics.isFeasible = constraintViolationNormalized == 0;

    if nargin >= 3 && ~isempty(commonPrecipitationVolume)
        validateattributes(commonPrecipitationVolume, {'numeric'}, ...
            {'scalar', 'real', 'finite', 'positive'}, mfilename, ...
            'commonPrecipitationVolume');
        diagnostics.candidateRetentionRate = 1 - ...
            candidateRunoffVolume / commonPrecipitationVolume;
        diagnostics.baselineRetentionRate = 1 - ...
            baselineRunoffVolume / commonPrecipitationVolume;
        diagnostics.signedResidualRate = ...
            diagnostics.baselineRetentionRate - ...
            diagnostics.candidateRetentionRate;
        diagnostics.violationRate = ...
            max(0, diagnostics.signedResidualRate);
    end
end
