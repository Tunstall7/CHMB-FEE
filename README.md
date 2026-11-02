Data and codes for "A selection framework for nature-based solutions based on hybrid modeling and multi-objective optimization".

# Data and Codes Usage Instructions for the Paper

## I. Data Overview

### (i) DEM Data

- **Format**: .tif
- **Spatial Resolution**: 30m × 30m
- **Data Content**: This data reflects the terrain elevation information of the study area, used for simulating the impact of terrain on hydrological processes, such as flow direction and slope, and is one of the fundamental data for constructing hydrological models.

### (ii) LUCC (Land Use/Land Cover Change) Data

- **Format**: .tif
- **Spatial Resolution**: 1km × 1km
- **Data Content**: It records in detail the land use types (such as arable land, forest land, construction land, etc.) and land cover conditions (such as vegetation cover, etc.) of the study area. By analyzing LUCC data, the impact of land use changes on the hydrological cycle and ecological processes can be studied, providing dynamic land use scenario inputs for model simulation.

### (iii) Soil Data

- **Format**: .tif
- **Attribute Content**: Includes key attributes such as soil type (such as loam, sandy soil, clay, etc.), soil texture (such as particle size distribution), soil permeability coefficient, soil water holding capacity, etc.
- **Spatial Resolution**: 1km × 1km
- **Data Content**: The soil data reflects the physical and hydrological characteristics of the soil in the study area and is crucial for simulating soil water movement and infiltration processes in hydrological models. Through soil data, the soil's interception of rainfall, infiltration, and groundwater recharge processes can be accurately depicted, providing soil attribute support for precise model simulation.

## II. HEC-HMS Automated Simulation Interface (HMS-MATLAB)

### (i) Overview

This is a set of MATLAB functions that automate the execution of HEC-HMS hydrological simulations and the extraction of model outputs. The code is designed to serve as the core evaluation engine inside any optimization or scenario-analysis loop, making it suitable for tasks such as parameter calibration, flood peak estimation, and water resources management optimization. It serves as one of the inputs for training the CHMB model and facilitates NbS optimization in this paper.

### (ii) Workflow

Calling `runModel(par)` triggers the following sequential pipeline:
- `updateBasin` — writes trial parameter values into the `.basin` file.
- `genScript` — generates a Jython compute script for HEC-HMS.
- `runHMS` — executes HEC-HMS from the command line.
- `genPyScript` — generates a Jython extraction script for HEC-DSSVue.
- `runPyScript` — executes HEC-DSSVue to export the simulated flow time series.
- `extractSim` — parses the exported file and returns the flow vector.

### (iii) Configuration

Before first use, update the path constants inside each function to match your local environment:
- `mdlPath` — HEC-HMS project directory.
- `expPath` — export directory for HEC-DSSVue output files.
- `hmsDir` — HEC-HMS installation directory (must contain `HEC-HMS.cmd`).
- `dssVue` — HEC-DSSVue installation directory (must contain `HEC-DSSVue.exe`).
- `runNames` — cell array of run names matching those defined in the HEC-HMS project.

### (iv) Usage

`runModel` accepts a parameter vector and returns a scalar or vector, making it directly compatible with any MATLAB objective optimizer (`fmincon`, `ga`, `particleswarm`, etc.).

## III. CHMB

### (i) Overview

This is a MATLAB script that automates the full pipeline of an LSTM-based time series forecasting model, from raw data ingestion through hyperparameter optimization to final prediction. The model uses Bayesian Optimization to automatically tune key network hyperparameters, eliminating the need for grid search. It is designed to serve as a self-contained forecasting engine that can be embedded in any scenario-analysis or sensitivity-study loop, making it suitable for tasks such as streamflow prediction, load forecasting, and multi-step time series regression.

### (ii) Workflow

Calling `runModel(par)` triggers the following sequential pipeline:

- **Data Ingestion and Preprocessing**
  - Column-type detection: The first data row is inspected to classify each column as categorical (character) or numeric.
  - Label encoding: Each unique string category is assigned a stable integer index using `unique` + `ismember`, producing a numeric matrix compatible with the network input.
  - NaN interpolation: Missing values are filled via `interp1(..., 'spline')` so that no sample is discarded.

- **Feature Engineering**
  -   The interpolated matrix is passed to `timeseries_process1`, which applies a sliding window of length `n_series` and stride 1 to build a 2-D feature matrix `Xf` paired with a target matrix `Yf`.
  -   The number of input dimensions equals `n_feat × n_series`; the number of output dimensions is controlled by `cfg.list`.

- **Dataset Partitioning and Normalization**
  - Samples are split chronologically into train / validation / test according to `cfg.split` ratios (no shuffling, preserving temporal order).
  - Z-score statistics (`mx`, `sx`, `my`, `sy`) are computed exclusively on the training partition and applied to all three splits to prevent data leakage.
  - The normalized matrices are converted to LSTM-compatible sequence cell arrays via the utility function `mat2seq`.

- **Bayesian Hyperparameter Optimization**
  - The optimizer is given a wall-clock budget of 14 hours and a maximum of `cfg.n_bo` iterations. The best configuration minimizes validation loss.
  - This is handled entirely by `OptimizeBayeLSTMS_and_CNNS1`.

- **Model Training**
  - Once optimal hyperparameters are found, `EvaluationData2` performs the final training run. The convergence history (RMSE and loss per epoch) is plotted automatically.
  - Trained networks are stored in the `nets{s, g}` cell, indexed by decomposition component `s` and output group `g`.

- **Inference and Metric Evaluation**
  - Predictions on all three partitions are obtained via `predict`, inverse-normalized, and aggregated across decomposition components.
  - The helper `eval_metrics` computes and prints KGE, MAE, RMSE, R², and NSE for each partition.

- **Rolling Forecast**
  - A post-validation rolling forecast is produced using `timeseries_process1_Pre` on the tail of the training data.
  - All predicted time steps are retained in the output matrix `Yhat_fwd [steps × outputs]`.

## IV. CHMB-Borg (for NbS optimization)

### (i) The usage instructions for Borg in MATLAB

- **Request Access**
  - Visit [http://borgmoea.org/](http://borgmoea.org/)
  - Click 'Request Access - Google Form' to fill out the application
  - Check your email (including spam folder) for the invitation link
  - Click the link in the email to accept the invitation

- **Download Source Code**
  - Download `BorgMOEA-master.zip` from the GitHub repository: [https://github.com/BorgMOEA/BorgMOEA](https://github.com/BorgMOEA/BorgMOEA)

- **Configure C/C++ Compiler**
  - In MATLAB Command Window, run:
    ```matlab
    mex -setup
    ```
  - If no compiler is configured:
    - Download MinGW-w64 compatible with your MATLAB version from [MathWorks](https://ww2.mathworks.cn/support/requirements/previous-releases.html)
    - Follow the installation prompts
  - If prompted to select a language, choose C++:
    - `mex -setup C++`

- **Compile Borg**
  - Navigate to the extracted `BorgMOEA-master` folder containing these files:
    - `borg.c`
    - `borg.h`
    - `mt19937ar.c`
    - `mt19937ar.h`
    - `nativeborg.cpp`
  - Run the compilation command:
    ```matlab
    mex nativeborg.cpp borg.c mt19937ar.c
    ```
  - Success indicator: Message displaying *"MEX completed successfully"* using *'MinGW64 Compiler (C++)'*.

### (ii) Integration with CHMB for NbS Optimization (CHMB-Borg)

Once successfully integrated, you can combine **Borg MOEA** with the **CHMB model** to optimize **Nature-based Solutions (NbS)**. This enables:

- **Key Features**
  - **Multi-objective Optimization**: Handles conflicting objectives (e.g., ecological benefits vs. economic costs) without requiring a priori weighting.
  - **Adaptive Search Strategy**: BORG's auto-adaptive operator selection dynamically switches between GA, DE, SPX, PCX, and UM operators based on problem characteristics.
  - **Epsilon-box Dominance Archive**: Maintains diverse Pareto-optimal solutions with controlled precision.
  - **Constraint Handling**: Supports both bound constraints and problem-specific constraints for realistic NbS scenarios.

- **Prerequisites**
  - MATLAB R2018b or later
  - BORG MOEA library (compiled MEX files for your platform)
  - CHMB model interface functions

- **Usage Example**
  ```matlab
  clear; close all; clc;

  %% 1. Problem Setup
  % Load CHMB scenario parameters
  config = loadCHMBConfig('scenario_A');

  % Define decision variables (NbS intervention intensities)
  % Example: [reforestation_area, wetland_restoration, urban_greening,
  %           sustainable_agriculture, forest_management, coastal_protection]
  numVars = 6;
  numObjs = 3;
  numConstr = 2;

  %% 2. Bounds Definition
  lb = zeros(1, numVars);  % Minimum intervention (0%)
  ub = config.maxIntervention;  % Maximum feasible intervention per zone

  %% 3. BORG Configuration
  % Epsilon values control solution granularity (tune based on objective scales)
  epsilon = [0.5;
             100;
             0.01];
  % Algorithm parameters (auto-adaptive ensemble)
  params = {'population.size', 200, ...
            'maxEvaluations', 50000, ...
            'initialization.mode', 'latinHypercube', ...
            'restart.mode', 'adaptive', ...
            'feedback.interval', 1000};

  %% 4. Objective Function Wrapper
  objFunc = @(vars) evaluateCHMB_NbS(vars, config);

  %% 5. Execute Optimization
  fprintf('Starting CHMB-NbS optimization...\n');
  [optimalVars, optimalObjs, metadata] = borg(numVars, numObjs, numConstr, ...
      objFunc, epsilon, lb, ub, params);
  ```

## VI. Applicability-Domain Index D

### (i) Overview

The applicability-domain index *D* is used to assess the similarity between candidate land-use configurations and historical land-use conditions. It is calculated as the minimum total variation distance between a candidate configuration and historical configurations, normalized by the maximum pairwise distance among historical configurations. A value of *D* greater than 1 indicates that the candidate lies beyond the historical distance range, suggesting potential extrapolation beyond the land-use conditions represented in the historical data.

### (ii) Input Data

- `candidate_land_use.xlsx` — Candidate land-use configurations under different flood scenarios.
- `historical_land_use.xlsx` — Historical land-use configurations used as reference conditions.
- Columns A–F in both files represent six land-use categories: cropland, forest, grassland, water, impervious surface, and barren land.

### (iii) Configuration and Usage

The Python script `calculate_AD_D.py` calculates the applicability-domain index for each candidate solution.

- Update `CANDIDATE_FILE`, `HISTORICAL_FILE`, and `OUTPUT_FILE` to match the local file paths.
- Install the required Python packages using `pip install numpy pandas openpyxl`.
- Run the script using `python calculate_AD_D.py`.

The script generates `AD_D_results.csv`, containing the calculated *D* values, total variation distances, and nearest historical configurations.

## VII. Constraints for NbS Optimization

### (i) Overview

Two constraints are incorporated into the NbS optimization framework to ensure that candidate land-use configurations satisfy hydrological and environmental feasibility requirements. The water retention capacity constraint prevents reductions in water retention relative to current conditions, while the hydroclimatic carrying-capacity constraint limits forest expansion according to local water-energy conditions.

### (ii) Water Retention Capacity Constraint

- **Description**

  This constraint requires the runoff volume under a candidate land-use configuration to be no greater than that under the current land-use conditions. Under identical rainfall conditions, this is equivalent to requiring the candidate water retention rate to be no lower than the baseline rate.

- **Input Data**
  - Candidate runoff volume simulated by HEC-HMS.
  - Baseline runoff volume under current land-use conditions.
  - Common precipitation volume, optional for calculating water retention rates.

- **Calculation and Usage**

  The MATLAB function `waterRetentionCapacityConstraint.m` calculates the normalized excess runoff volume. A constraint violation of zero indicates a feasible solution, whereas a positive value indicates a violation.

  Call `waterRetentionCapacityConstraint(candidateRunoffVolume, baselineRunoffVolume)` to obtain the constraint violation and associated diagnostic results.

### (iii) Hydroclimatic Carrying-Capacity Constraint

- **Description**

  This constraint limits the forest proportion in each subbasin according to its maximum supportable level under local hydroclimatic conditions. It prevents land-use configurations from exceeding the predefined forest carrying capacity while maintaining spatial allocation and area-balance requirements.

- **Input Data**
  - Six land-use proportions representing the candidate configuration.
  - Subbasin areas and baseline land-use distributions.
  - Precomputed forest carrying-capacity limits for individual subbasins.

- **Calculation and Usage**

  The MATLAB function `hydroclimaticCarryingCapacityConstraint.m` evaluates forest allocation feasibility by checking the prescribed carrying-capacity limits and spatial allocation requirements.

  Call `hydroclimaticCarryingCapacityConstraint(decisionShares, config)` to obtain the constraint violation and spatial allocation results.

  The configuration structure can be obtained using `getLandUseConstraintConfig.m`, which reads the required subbasin characteristics and precomputed forest capacity limits from the supporting input files.

### (iv) Additional Notes

- Both MATLAB functions can be used independently to evaluate candidate solutions or incorporated into the Borg optimization framework.
- A constraint violation of zero indicates feasibility, while a positive value indicates a violation.
- Users should update the relevant file paths and ensure that the required supporting data are available.
- Reproducing the original optimization results requires consistent hydrological simulations, baseline conditions, and forest carrying-capacity limits.
- The two constraints presented here serve as examples. In practical applications, the types, definitions, and number of constraints can be adjusted according to the specific characteristics and requirements of the study area.
