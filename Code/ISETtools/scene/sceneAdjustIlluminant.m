function scene = sceneAdjustIlluminant(scene,illEnergy,preserveMean)
%Adjust the current scene illuminant to the value in data
%
%  scene = sceneAdjustIlluminant(scene,illEnergy,preserveMean)
%
% The scene radiance is scaled by dividing the current illuminant and
% multiplying by the new illEnergy.  The reflectance is preserved.
%
% Parameters
%  scene:      A scene structure, or the current scene will be assumed
%  illuminant: Either a file name to spectral data or a vector (same length
%    as scene wave) defining the illuminant in energy units
%  preserveMean:  Scale result to preserve mean illuminant
%
% If the current scene has no defined illuminant, we assume that it has a
% D65 illumination
%
% The scene luminance is preserved by this transformation.
%
% Example:
%    scene = sceneCreate;   % Default is MCC under D65
%    scene = sceneAdjustIlluminant(scene,'Horizon_Gretag.mat');
%    vcReplaceAndSelectObject(scene); sceneWindow;
%
%    bb = blackbody(sceneGet(scene,'wave'),3000);
%    scene = sceneAdjustIlluminant(scene,bb);
%    vcReplaceAndSelectObject(scene); sceneWindow;
%
%    bb = blackbody(sceneGet(scene,'wave'),6500,'energy');
%    figure; plot(wave,bb)
%    scene = sceneAdjustIlluminant(scene,bb);
%    vcReplaceAndSelectObject(scene); sceneWindow;
%
% Copyright ImagEval Consultants, LLC, 2010.

if ieNotDefined('scene'),        scene = vcGetObject('scene'); end
if ieNotDefined('preserveMean'), preserveMean = true; end

% Make sure we have the illuminant data in the form of energy
wave = sceneGet(scene,'wave');
if ieNotDefined('illEnergy')
    % Read from a user-selected file
    fullName = vcSelectDataFile([]);
    illEnergy = ieReadSpectra(fullName,wave);
elseif ischar(illEnergy)
    % Read from the filename sent by the user
    fullName = illEnergy;
    if ~exist(fullName,'file'), error('No file %s\n',fullName);
    else  illEnergy = ieReadSpectra(fullName,wave);
    end
else
    % User sent numbers.  We check for numerical validity next.
    fullName = '';
end

% We check the illuminant energy values.
if max(illEnergy) > 10^5
    % Energy is not this big.
    warning('Illuminant energy values are high; may be photons, not energy.')
elseif isequal(max(isnan(illEnergy(:))),1) || isequal(min(illEnergy(:)),0)
    % warndlg('NaNs or zeros present in proposed illuminant over this wavelength range. No transformation applied.');
    % Commented out by HB. I actually sometimes need to set a new
    % illuminant that is ideally zero
    % pause(3);
    % return;
end

% Start the conversion
curIll = sceneGet(scene,'illuminant photons');
if isempty(curIll)
    % We  treat this as an opportunity to create an illuminant, as in
    % sceneFromFile (or vcReadImage). Assume the illuminant is D65.  Lord
    % knows why.  Maybe we should do an illuminant estimation algorithm
    % here.
    disp('Old scene.  Creating D65 illuminant')
    wave   = sceneGet(scene,'wave');
    curIll = ieReadSpectra('D65',wave);   % D65 in energy units
    scene  = sceneSet(scene,'illuminant energy',curIll);
    curIll = sceneGet(scene,'illuminant photons');
end

% Current mean luminance may be preserved
mLum     = sceneGet(scene,'mean luminance');
if isnan(mLum) 
    [lum, mLum] = sceneCalculateLuminance(scene);
    scene = sceneSet(scene,'luminance',lum);
end

% Converts illEnergy to illPhotons.  Deals with different illuminant
% formats.  If preserve reflectance or not, do slightly different things.
curIll = double(curIll);
switch sceneGet(scene,'illuminant format')
    case 'spectral'
        % In this case the illuminant is a vector.  We convert to photons
        illPhotons = Energy2Quanta(illEnergy,wave);

        % Find the multiplier ratio 
        illFactor  = illPhotons ./ curIll;
        illFactor(isnan(illFactor) | isinf(illFactor)) = 0;
        % Adjust both the radiance data and the illuminant by the illFactor

        skipIlluminant = 0;  % Don't skip changing the illuminant (do change it!)
        scene = sceneSPDScale(scene,illFactor,'*',skipIlluminant);
        
    case 'spatial spectral'
        if ~isequal(size(illEnergy),size(illEnergy))
            error('Spatial spectral illuminant size mis-match');
        end
        
        [newIll,r,c] = RGB2XWFormat(illEnergy);
        newIll = Energy2Quanta(wave,newIll');
        newIll = XW2RGBFormat(newIll',r,c);
        
        % Get the scene radiance
        photons = sceneGet(scene,'photons');
        
        % Divide the radiance photons by the current illuminant and then
        % multiply by the new illuminant.  These are the radiance photons
        % under the new illuminant.  This preserves the reflectance.
        photons = (photons ./ curIll) .* newIll;
        
        % Set the new radiance back into the scene
        scene = sceneSet(scene,'photons',photons);
        
        % Set the new illuminant back into the scene
        scene = sceneSet(scene,'illuminant photons',newIll);
end

% Make sure the mean luminance is unchanged.
if preserveMean  % Default is true
    scene = sceneAdjustLuminance(scene,mLum);
end

scene = sceneSet(scene,'illuminant comment',fullName);

return;

