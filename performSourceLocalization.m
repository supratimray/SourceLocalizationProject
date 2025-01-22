% This program performs source localization using fieldtrip

function sourceData = performSourceLocalization(data,displayResultsFlag,methodSourceLoc,capType,methodHeadModel,methodSourceModel,commonFilterFlag,stRange,freqRange)

if ~exist('displayResultsFlag','var');  displayResultsFlag = 0;         end
if ~exist('methodSourceLoc','var');     methodSourceLoc = 'dics';       end
if ~exist('capType','var');             capType = 'actiCap64';          end
if ~exist('methodHeadModel','var');     methodHeadModel = 'bemcp';                end
if ~exist('methodSourceModel','var');   methodSourceModel = 'basedonresolution';  end
if ~exist('commonFilterFlag','var');    commonFilterFlag = 1;           end
if ~exist('stRange','var');             stRange = [0.25 0.75];          end
if ~exist('freqRange','var');           freqRange = [20 34];            end

%%%%%%%%%%%%%%%%%%%%%%%%%% Get Source Model %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
model = prepareSourceModel(0,capType,methodHeadModel,methodSourceModel);

%%%%%%%%%%%%%%%%%%%%%%% Data Preprocessing %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 1. Interpolate the bad electrodes

% Get bad channel names from indices
badChannels = data.label(data.badElecs);

% % Prepare neighbours using distance method
% % note: requires the neighours file witin fieldtrip/tempate directory
% cfg = [];
% cfg.method = 'distance';    % Use distance method
% cfg.neighbourdist = 50;     % Maximum distance between neighbours
% cfg.elec = model.elec;
% cfg.feedback = 'no';       % Show feedback about the neighbours
% neighbours = ft_prepare_neighbours(cfg);

% Prepare neighbours using template method - gives slightly better results
% note: requires the neighours file witin fieldtrip/tempate directory
cfg = [];
cfg.method = 'template';    % Use template method instead of spline
cfg.template = 'elec1010';  % Using standard 10-10 template
cfg.layout = 'elec1010';    % Specify the layout file
cfg.feedback = 'no';       % Show feedback about the neighbours
neighbours = ft_prepare_neighbours(cfg);

% interpolate
cfg = [];
cfg.method = 'spline';      % Keep spline for interpolation
cfg.badchannel = badChannels;  % Using the extracted bad channel names
cfg.neighbours = neighbours;    % Use the prepared neighbours
data = ft_channelrepair(cfg, data);

% 2. Perform average reference
cfg = [];
cfg.demean = 'yes';         % Remove mean value
cfg.reref = 'yes';          % Re-reference the data
cfg.refmethod = 'avg';      % Average reference
cfg.refchannel = 'all';     % Use all channels for referencing
data = ft_preprocessing(cfg, data); % average reference the data

% 3. Prepare baseline and stimulus segments for analysis
cfg = [];
cfg.toilim = [-diff(stRange) 0];
dataPre = ft_redefinetrial(cfg, data);
cfg.toilim = stRange;
dataPost = ft_redefinetrial(cfg, data);

% 4. Perform cross spectral analysis
cfg = [];
cfg.method    = 'mtmfft';
cfg.output    = 'powandcsd';
cfg.taper     = 'dpss';
cfg.tapsmofrq = diff(freqRange)/2;
cfg.foi       = mean(freqRange);

freqPre       = ft_freqanalysis(cfg, dataPre);
freqPost      = ft_freqanalysis(cfg, dataPost);

if commonFilterFlag
    dataAll = ft_appenddata([], dataPre, dataPost);
    freqAll = ft_freqanalysis(cfg, dataAll);
end

%%%%%%%%%%%%%%%%%%%%%%%%% Source Localization %%%%%%%%%%%%%%%%%%%%%%%%%%%%%

cfg = [];
cfg.method = methodSourceLoc;
cfg.grid = model.leadfield;
cfg.headmodel = model.headmodel;
cfg.frequency = freqPre.freq;

if strcmp(methodSourceLoc,'dics') % Special parameters for dics
    cfg.dics.projectnoise = 'yes';
    cfg.dics.lambda = '2%';
    cfg.dics.keepfilter = 'yes';
    cfg.dics.realfilter = 'yes';

    if commonFilterFlag  % Compute a common filter for both pre and post
        sourceAll = ft_sourceanalysis(cfg, freqAll);
        cfg.sourcemodel.filter = sourceAll.avg.filter; % Common filter
    end
end

sourcePre = ft_sourceanalysis(cfg, freqPre);
sourcePost = ft_sourceanalysis(cfg, freqPost);

% Calculate normalized source power
sourceData = sourcePost;
%   sourceData.avg.pow = (sourcePost.avg.pow - sourcePre.avg.pow) ./ sourcePre.avg.pow;
sourceData.avg.pow = 10*(log10(sourcePost.avg.pow) - log10(sourcePre.avg.pow)); % change in power in decibels

if displayResultsFlag
    % Source Data Visualization - ortho
    % Interpolate source data onto MRI for visualization
    tmp = load('mri_orig.mat');
    mri_orig = tmp.mri;
    cfg = [];
    mri_resliced_orig = ft_volumereslice(cfg, mri_orig);

    cfg = [];
    cfg.downsample = 2;
    cfg.parameter = 'pow';
    sourceDataInterp = ft_sourceinterpolate(cfg, sourceData, mri_resliced_orig);

    % Visualize interpolated source data
    cfg = [];
    cfg.method = 'ortho';
    cfg.funparameter = 'pow';
    cfg.funcolorlim = 'maxabs';
    cfg.funcolormap = 'jet';        % Use jet colormap for better contrast

    ft_sourceplot(cfg, sourceDataInterp);

    % % Source Data Visualization - surface
    % cfg = [];
    % cfg.nonlinear = 'no';
    % sourceDataSurface = ft_volumenormalise(cfg, sourceDataInterp); % converts to MNI coordinates
    %
    % cfg = [];
    % cfg.method         = 'surface';
    % cfg.funparameter   = 'pow';
    % cfg.maskparameter  = cfg.funparameter;
    % cfg.funcolormap    = 'jet';
    % cfg.opacitymap     = 'rampup';
    % cfg.projmethod     = 'nearest';
    % cfg.surffile       = 'surface_white_both.mat';
    % cfg.surfdownsample = 10;
    % ft_sourceplot(cfg, sourceDataSurface);
    % view ([90 0]);
end
end