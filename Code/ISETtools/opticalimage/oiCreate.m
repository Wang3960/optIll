function [oi,val] = oiCreate(oiType,varargin)
%Create an optical image structure.
%
%   oi = oiCreate(oiType,varargin)
%
% If val is passed in, the optical image is set to be the number val.
% Otherwise, a new number is selected.
%
% If optics is passed in, this is  attached to the optical image. Otherwise
% the default optics (diffraction limited) are used.
%
% By default, the new optical image is not added to the set of optical
% image objects stored in vcSESSION.  If you want it added, addObject = 1.
% Normally we add it when ready with a ieAddObject
%
% OI types include: default, uniformD65, uniformEE.  The latter two are
% used only for lux-snr testing and related.  Almost always we simply
% create a default optical image with a diffraction-limited lens attached.
%
% The spectrum is not set in this call because it is normally inherited
% from the scene.  To specify a spectrum for the optical image use
%      oi = oiCreate('default');
%      oi = initDefaultSpectrum('hyperspectral');
%
% Types of OI:
%  {'diffraction limited'} -  Diffraction limited optics, no diffuser or
%                             data (Default)
%  {'shift invariant'}     -  General high resolution shift-invariant
%                             model set up. Like human but pillbox OTF
%  {'human'}      - Inserts human shift-invariant optics
%  {'ray trace'}  - Ray trace OI
%
% Some cases with data that avoid any calculation from the scene.  These
% are to simplify testing aspects of the sensor properties
%
%  {'uniform d65'} - Turns off offaxis to make uniform D65 image
%  {'uniform ee'}  - Turns off offaxis and creates uniform EE image
%
% Example:
%   oi = oiCreate;
%   oi = oiCreate('diffraction limited');  % As above
%   oi = oiCreate('human');
%   oi = oiCreate('ray trace',rtOpticsFile);
%   oi = oiCreate('uniform d65');  % D65 used for lux-sec vs. snr measurements.
%   oi = oiCreate('uniform EE');   % Create an equal energy
%   oi = oiCreate('uniform EE',64,(380:4:1068)); % Set size and wave
%
% See also:  sceneCreate
%
% Copyright ImagEval Consultants, LLC, 2003.

if ieNotDefined('oiType'),  oiType = 'diffraction limited'; end
if ieNotDefined('val'),     val = vcNewObjectValue('OPTICALIMAGE'); end
if ieNotDefined('optics'),  optics = opticsCreate('default'); end

% We used to automatically add created OI objects to the list.  Stopped
% doing this July, 2012
if ieNotDefined('addObject'), addObject = 0; end

% Default is to use the diffraction limited calculation
oi.type = 'opticalimage';
oi.name = vcNewObjectName('opticalimage');
% oi = oiSet(oi,'bit depth',32);  % Single precision.

oiType = ieParamFormat(oiType);
switch oiType 
    case {'diffractionlimited','standard(1/4-inch)','default'}
        oi = oiSet(oi,'optics',optics);
        
        % Set up the default glass diffuser with a 2 micron blur circle, but
        % skipped
        oi = oiSet(oi,'diffuser method','skip');
        oi = oiSet(oi,'diffuser blur',2*10^-6);
        oi = oiSet(oi,'consistency',1);

    case {'shiftinvariant'}
        % Rather than using the diffraction limited call to make the OTF,
        % we use some other method, perhaps wavefront.
        % Human is a special form of shift-invariant.  We might make
        % shiftinvariant-wvf or just wvf in the near future after
        % experimenting some.
        oi = oiSet(oi,'optics',opticsCreate('shift invariant',oi));
        oi = oiSet(oi,'name','SI');
        oi = oiSet(oi,'diffuserMethod','skip');
        oi = oiSet(oi,'consistency',1);

    case {'raytrace'}
        % Create the default ray trace unless a file name is passed in
        oi = oiCreate('default');
        rtFileName = fullfile(isetRootPath,'data','optics','rtZemaxExample.mat');
        if ~isempty(varargin), rtFileName = varargin{1}; end
        load(rtFileName,'optics');
        oi = oiSet(oi,'optics',optics);
        
    case {'human'}
        % Marimont and Wandell human optics model.  For more extensive
        % biological modeling, see the ISETBIO derivative which has now
        % expanded and diverged from ISET.
        oi = oiCreate('default');
        oi = oiSet(oi,'diffuserMethod','skip');
        oi = oiSet(oi,'consistency',1);
        oi = oiSet(oi,'optics',opticsCreate('human'));
        oi = oiSet(oi,'name','human-MW');
        
    case {'uniformd65'}
        % Uniform, D65 optical image.  No cos4th falloff, huge field of
        % view (120 deg). Used in lux-sec SNR testing and scripting
        oi = oiCreateUniformD65;
        
    case {'uniformee','uniformeespecify'}
        % Uniform, equal energy optical image. No cos4th falloff. Might be used in
        % lux-sec SNR testing or scripting.  Not really used now
        % (5.3.2005).
        wave = 400:10:700; sz = 32;
        if length(varargin) >= 1, sz = varargin{1}; end
        if length(varargin) >= 2, wave = varargin{2}; end
        oi = oiCreateUniformEE(sz,wave);
        
    otherwise
        error('Unknown oiType');
end

return;

%--------------------------------------------
function oi = oiCreateUniformD65
%  Create a spatially uniform, D65 image with a very large field of view.
%  The optical image is created without any cos4th fall off so it can be
%  used for lux-sec SNR testing.  The diffraction limited fnumber is set
%  for no blurring.
%

scene = sceneCreate('uniform d65');
scene = sceneSet(scene,'hfov',120);
ieAddObject(scene);

oi = oiCreate('default');
oi = oiSet(oi,'optics fnumber',1e-3);
oi = oiSet(oi,'optics offaxis method','skip');
oi = oiCompute(scene,oi);


return;

%---------------------------------------------
function oi = oiCreateUniformEE(sz,wave)
%  Create a spatially uniform, equal energy image with a very large field
%  of view. The optical image is created without any cos4th fall off so it
%  can be used for lux-sec SNR testing.  The diffraction limited fnumber is
%  set for no blurring.

scene = sceneCreate('uniform EE',sz,wave);
scene = sceneSet(scene,'hfov',120);
ieAddObject(scene);

oi = oiCreate('default');
oi = oiSet(oi,'optics fnumber',1e-3);
oi = oiSet(oi,'optics offaxis method','skip');
oi = oiCompute(scene,oi);

return;
