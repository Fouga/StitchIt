function im = combCorrector(im,sectionDir,coords,userConfig)
    % crops tiles for stitchit tileLoad
    %
    % function im = stitchit.tileload.combCorrector(im,sectionDir,coords,userConfig)
    %
    % Purpose
    % There are multiple tileLoad functions for different imaging systems
    % but all do the comb correction of tiles the same way using this function. 
    % This function is called by tileLoad.
    %
    % Inputs
    % im - the image stack to crop
    % sectionDir - Path to the directory containing section data. 
    % coords - the coords argument from tileLoad
    % userConfig - [optional] this INI file details. If missing, this 
    %              is loaded and cropping params extracted from it. 
    %
    % Outputs
    % im - the cropped stack. 
    %
    %
    % Rob Campbell - Basel 2017

    if nargin<4 || isempty(userConfig)
        userConfig = readStitchItINI;
    end
    
    % if finds txt for shift - do the rows correction, otherwise Robs
    % corrections
    avDir = [userConfig.subdir.rawDataDir,filesep,userConfig.subdir.averageDir];
    if ~exist([avDir '/MakeL1Correction.txt'])
        im = correct_phases(im,sectionDir,coords,userConfig);
    else
        im = correct_rowsShift(im,coords,userConfig);
    end
    
    
    function im = correct_phases(im,sectionDir,coords,userConfig)
        % DUPE
        %TODO: this is duplicated from tileLoad. 
        % it's easier this way but if it takes too long, we can feed in these
        % variables from tileLoad
        % 
        %Load tile index file (this function isn't called if the file doesn't exist so no 
        %need to check if it's there.
        tileIndexFile=sprintf('%s%stileIndex',sectionDir,filesep);
        index=readTileIndex(tileIndexFile);


        %Find the index of the optical section and tile(s)
        f=find(index(:,3)==coords(2)); %Get this optical section 
        index = index(f,:);

        indsToKeep=1:length(index);

        if coords(3)>0
            f=find(index(:,4)==coords(3)); %Row in tile array
            index = index(f,:);
            indsToKeep=indsToKeep(f);
        end

        if coords(4)>0
            f=find(index(:,5)==coords(4)); %Column in tile array
            index = index(f,:);
            indsToKeep=indsToKeep(f);
        end
        %% /DUPE

        corrStatsFname = sprintf('%s%sphaseStats_%02d.mat',sectionDir,filesep,coords(2));

        if ~exist(corrStatsFname,'file')
            fprintf('%s. phase stats file %s missing. \n',mfilename,corrStatsFname)
        else
            load(corrStatsFname);
            phaseShifts = phaseShifts(indsToKeep);
            im = applyPhaseDelayShifts(im,phaseShifts);
        end

        
    function imShift = correct_rowsShift(im,coords,userConfig)
        disp('L1 comb correction \n');
        imShift = uint16(zeros(size(im)));
        avDir = [userConfig.subdir.rawDataDir,filesep,userConfig.subdir.averageDir];
        A=load([avDir '/MakeL1Correction.txt']);
        l1 = A(1,4);
        ind = find(A(:,1)==coords(1) & A(:,2)==coords(2));
        shiftPatches = A(ind,5:end);
        [M N P] = size(im);
        q = 1:floor(N/l1);
        sizVert = [1,l1*q];
        IMall = cell(floor(N/l1)+1,1);
        for imS = 1:P
            rgbIm = im(:,:,imS);
            Im_shift = reshape(shiftPatches(imS,:),floor(M/l1)+1,floor(N/l1)+1)';
            for i = 1:floor(M/l1)+1
                IM1 = [];
                for j = 1:floor(N/l1)+1
                    shift_optim = Im_shift(i,j);
                    % extract patch in a tile
                     imagePatche = imcrop(rgbIm,[sizVert(j) sizVert(i) l1-1 l1-1]);
                    if j==floor(N/l1)+1 && i~=floor(N/l1)+1
                       imagePatche = imcrop(rgbIm,[sizVert(j) sizVert(i)  N-sizVert(j)-1 l1-1]);
                    elseif i==floor(N/l1)+1 && j~=floor(N/l1)+1
                       imagePatche = imcrop(rgbIm,[sizVert(j) sizVert(i) l1-1  M-sizVert(i)-1]);
                    elseif j==floor(N/l1)+1 && i==floor(N/l1)+1
                       imagePatche = imcrop(rgbIm,[sizVert(j) sizVert(i) N-sizVert(j)-1   M-sizVert(i)-1]);
                    end

                    rgbIm_shift =shiftImage(imagePatche,shift_optim);
                    IM1 = cat(2,IM1,rgbIm_shift);
                end
                IMall{i,1} = IM1;
            end
            RGBim1=cat(1,IMall{1:floor(N/l1)+1,1});
        
%         for i = 1:size(im,3)
%             Im = im(:,:,i);
%             Im_shift = Image_shift(:,i);
%             Im_stripe_size = stripe_size(:,i);
%             start_stripe = 0;
%             for S = 1:length(Im_stripe_size)
%                 stripes = Im_stripe_size(S);% no
%                 shift = Im_shift(S);    
%                 % take only part of the tile image due to different shifts
%                 im_stripe = Im(:,start_stripe+1:stripes);
%                 % shift to the left or right
%                 if shift>=0
%                     % shift to the left
%                     im1_shift = im_stripe;
%                     for rows = 2:2:size(im1_shift,1)
%                         im1_shift(rows,shift+1:end) = im_stripe(rows,1:end-shift);
%                     end
% 
%                 else
%                     %     % shift to the right
%                     shift = abs(shift);
%                     im1_shift = im_stripe;
%                     for rows = 2:2:size(im1_shift,1)
%                         im1_shift(rows,1:end-shift) = im_stripe(rows,shift+1:end);
%                     end
% 
%                 end
%                 % rebuild the image but shifted
%                 Im(:,start_stripe+1:stripes) = im1_shift;
%                 start_stripe = stripes;
             imShift(:,:,imS) = RGBim1;
        end
    
    function im1_shift = shiftImage(Image, shift)

       if shift>=0
            % shift to the left
            im1_shift = Image;
            for rows = 2:2:size(im1_shift,1)
                im1_shift(rows,shift+1:end) = Image(rows,1:end-shift);
            end

       else
            %     % shift to the right
            shift = abs(shift);
            im1_shift = Image;
            for rows = 2:2:size(im1_shift,1)
                im1_shift(rows,1:end-shift) = Image(rows,shift+1:end);
            end
       end
    %     
    %     im(:,:,1) = im1_shift;
    %     im(:,:,2) = im2_shift;
    %     im(:,:,3) = im3_shift;

%          im = cat(3, im1_shift,im2_shift,im3_shift);



