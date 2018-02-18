% control_acbar: control software for ACBAR electrodynamic balance
%
% originally developed in Huisman Lab, Union College
% adapted in Keutsch Lab, Harvard University
%
% dependencies:
%   DS345Device.m : Matlab class for serial communication with function
%                   generator
%   injector.ino : Arduino script for droplet injection pulse generation

function varargout = control_acbar(varargin)
%%
% creates acbar_main window
main=figure('visible','off',...
    'Name','acbar_main',...
    'Position',[50,600,300,200],...
    'MenuBar','none',...
    'ToolBar','none');

set(main,'visible','on');
delete(timerfindall);

%%
% on acbar_main, build the buttons and displays
save_checkbox=uicontrol('parent',main,'style','checkbox',...
    'string','Save file',...
    'value',0,'position',[10 10 140 20]);

slowupdatetext=uicontrol(main,'style','text','string','Saves when checked',...
    'position',[100 10 100 15]);

save_filename=uicontrol('parent',main,'style','edit',...
    'string','Enter Particle ID Here',...
    'position',[10 40 140 20],...
    'callback',@checkfile_exist);

fasttimer_button=uicontrol(main,...
    'style','togglebutton','value',0,...
    'position',[10 130 150 20],...
    'string','Start background timer',...
    'callback',@fasttimer_startstop);

errorcatchtimer_button=uicontrol(main,...
    'style','togglebutton','value',0,...
    'position',[10 160 150 20],...
    'string','Start error catch timer',...
    'callback',@errortimer_startstop);

% build_button=uicontrol(main,...f
%     'style','togglebutton','value',0,...
%     'position',[200 100 150 20],...
%     'string','Build voltage Window',...
%     'callback',@build_voltage_window);

MKSscramcomms=uicontrol(main,'style','pushbutton',...
    'position',[175 75 110 20],'string','SCRAM COMMS',...
    'callback',@SCRAM_COMMS);


flush_button=uicontrol(main,'style','pushbutton',...
    'position',[175 45 110 20],'string','Flush All Data',...
    'callback',@Flush_data);

microscope_checkbox=uicontrol('parent',main,'style','checkbox',...
    'string','Microscope subVI',...
    'value',0,'position',[175 175 140 20],...
    'callback',@microscope_checkbox_fcn,'visible','off');

fringe_checkbox=uicontrol('parent',main,'style','checkbox',...
    'string','Fringe subVI',...
    'value',0,'position',[175 150 140 20],...
    'callback',@fringe_checkbox_fcn,'visible','off');

fastupdatetext=uicontrol(main,'style','text','string','Fast update: 0.??? s',...
    'position',[10 100 150 15]);

slowupdatetext=uicontrol(main,'style','text','string','Slow update at ??:??:??',...
    'position',[10 70 150 15]);

%% Initialization tasks for main window
fasttimer = timer('TimerFcn',@fasttimerFcn,'ExecutionMode','fixedRate',...
    'Period',0.10);

errorcatchtimer = timer('TimerFcn',@errorcatchFcn,'ExecutionMode','fixedRate',...
    'Period',30);
%start(errorcatchtimer);

microscope_window_handle=[];
fringe_window_handle=[];
arduino_window_handle=[];
MKS_window_handle=[];
Andor_window_handle=[];
hygrometer_window_handle=[];

%set Flags for camera
setappdata(main,'camera1Flag',0)
setappdata(main,'camera2Flag',0)
setappdata(main,'microscope_subVI',0)
setappdata(main,'fringe_subVI',0)
setappdata(main,'FrameNumber',0);
setappdata(main,'UPSInumber',1); %default to sensor 1
setappdata(main,'AndorFlag',0);
setappdata(main,'AndorImage',[]);
setappdata(main,'AndorTimestamp',[]);
setappdata(main,'AndorImage_startpointer',0);
setappdata(main,'AndorCalPoly',[]);
setappdata(main,'VoltageData',[]);
setappdata(main,'UPSIdata',[]);
setappdata(main,'RampFlag',0);
setappdata(main,'MKSdatalog',[]);
setappdata(main,'Laudadatalog',[]);
setappdata(main,'Julabodatalog',[]);
setappdata(main,'fringe_timestamp',[]);
setappdata(main,'fringe_compressed',[]);
setappdata(main,'image_timestamp',[]); %tunestamp for images
setappdata(main,'fringe_image',[]);
setappdata(main,'microscope_image',[]);
setappdata(main,'hygrometer_data',[]);
setappdata(main,'voltage_data_nofeedback',[]);

build_microscope_window;
build_fringe_window;
build_arduino_window;
build_MKS_window;
build_Andor_window;
build_hygrometer_window;

    function checkfile_exist(source,eventdata)
        %add code here to make sure that the filename that was just typed in does not already exist in the folder
        %this will present accidental overwrite of data!\
        value=source.String;
        if(exist([value '.mat'],'file')==2)
            source.String='choose a new file name';
        end
    end

%% functions that build windows and initialize variables
    function build_microscope_window(source,eventdata)
        microscope_window_handle=figure('visible','off',...
            'Name','microscope',...
            'Position',[500,500,900,300],...
            'MenuBar','none',...
            'ToolBar','none');
        
        set(microscope_window_handle,'visible','on')
        

        
        %create a button that arms the camera
        marm=uicontrol(microscope_window_handle,'style','togglebutton','String','Run Camera',...
            'Value',0,'position',[10 100 100 20],...
            'Callback',@microscope_camera_arm);
        
        %create a static text box to show camera status
        mstatus_display=uicontrol(microscope_window_handle,'style','text','string','Camera Status',...
            'position',[120 90 50 30]);
        set(mstatus_display,'backgroundcolor',[1 1 0]);
        
        %create slider for gain
        mgain_slider=uicontrol(microscope_window_handle,'style','slider',...
            'min',0,'max',18,'value',2,...
            'sliderstep',[0.01 0.2],...
            'position',[10 70 100 20],...
            'Callback',@change_microscope_gain);
        
        %create a static text to show camera gain
        mgain_display=uicontrol(microscope_window_handle,'style','text',...
            'string',[num2str(get(mgain_slider,'value'),'%2.1f') ' dB'],...
            'position',[120 70 50 15]);
        
        %create slider for shutter
        mshutter_slider=uicontrol(microscope_window_handle,'style','slider',...
            'min',0.011,'max',33.2,'value',1,...
            'sliderstep',[0.001 0.2],...
            'position',[10 40 100 20],...
            'Callback',@change_microscope_shutter);
        
        %create a static text to show camera shutter
        mshutter_display=uicontrol(microscope_window_handle,'style','text',...
            'string',[num2str(get(mgain_slider,'value')) ' ms'],...
            'position',[120 40 50 15],...
            'Callback',@change_microscope_shutter);
        
        mfullscreen_button=uicontrol(microscope_window_handle,'style','pushbutton',...
            'string','Full Screen',...
            'position',[10 10 100 20],...
            'Callback',@microscope_fullscreen);
        
        %create a tab group for voltage plot
        tgroup1=uitabgroup('parent',microscope_window_handle,'position',[0.2 0.05 0.4 0.9]);
        tg1t1=uitab('parent',tgroup1,'Title','Microsope');
        tg1t2=uitab('parent',tgroup1,'Title','Voltage Plot');
        
        %create the axes for the microscope camera
        ax1=axes('parent',tg1t1);
        set(ax1,'xticklabel',[]);
        set(ax1,'xtick',[]);
        set(ax1,'yticklabel',[]);
        set(ax1,'ytick',[]);
        %set the axes to not reset plot propertes
        set(ax1,'nextplot','add');
        set(ax1,'ydir','reverse');
        set(ax1,'xlim',[0 640],'ylim',[0 480])
        set(ax1,'Unit','normalized','Position',[0 0 1 1])
        
        %create the axes for the voltage display
        ax20=axes('parent',tg1t2);
        set(ax20,'nextplot','replacechildren');
        %colormap(ax20,'jet')
        set(ax20,'xlimmode','auto')
        
        midealy_label=uicontrol(microscope_window_handle,'style','text',...
            'position',[10 220 100 20],'horizontalalignment','center',...
            'string','y-axis set point');
        
        midealy=uicontrol(microscope_window_handle,'style','edit',...
            'position',[10 200 100 20],'string','480',...
            'callback',@setidealY);
        
        setappdata(main,'IdealY',480);
        
        midealy_get=uicontrol(microscope_window_handle,'style','pushbutton',...
            'callback',@getidealy,...
            'position',[115 200 50 20],'string','get','enable','off');
        
        mhold_position=uicontrol(microscope_window_handle,'style','togglebutton',...
            'string','Hold Position',...
            'position',[10 160 100 20],...
            'callback',@mholdposition);
        
        ax1clear=uicontrol(microscope_window_handle,'style','pushbutton','string','cla(ax1)',...
            'position',[10 130 100 20],...
            'callback',{@clearaplot,ax1});
        
        initialize_microscope_variables;
        
        %build SRS control
        %check which serial ports are available
        serialinfo=instrhwinfo('serial');
        
        SRS1label=uicontrol(microscope_window_handle,'style','text',...
            'String','DC Fcn Generator',...
            'position',[525 250 100 20]);
        
        SRS1selectbox=uicontrol(microscope_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[650 250 100 20]);
        
        SRS1openclose=uicontrol(microscope_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[775 250 100 20],...
            'callback',@SRScommsDC,'tag','DC');
        
        SRS2label=uicontrol(microscope_window_handle,'style','text',...
            'String','AC Fcn Generator',...
            'position',[525 220 100 20]);
        
        SRS2selectbox=uicontrol(microscope_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[650 220 100 20]);
        
        SRS1openclose=uicontrol(microscope_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[775 220 100 20],...
            'callback',@SRScommsAC,'tag','AC'); %NEED TO FIX THIS CALLBACK?
        
        
        DClabel=uicontrol(microscope_window_handle,'style','text',...
            'string','DC OFFS',...
            'Position',[550 195 100 20]);
        
        DCOFFS=uicontrol(microscope_window_handle,'style','text',...
            'string','??? V ','position',[550 180 100 20]);
        
        DCOFFS_plus10=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 160 80 20],'string','+10',...
            'callback',@newSRS,'tag','DC OFFS +10',...
            'enable','off');
        
        DCOFFS_plus1=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 130 80 20],'string','+1',...
            'callback',@newSRS,'tag','DC OFFS +1',...
            'enable','off');
        
        DCOFFS_plus01=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 100 80 20],'string','+0.1',...
            'callback',@newSRS,'tag','DC OFFS +0.1',...
            'enable','off');
        
        DCOFFS_less01=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 70 80 20],'string','-0.1',...
            'callback',@newSRS,'tag','DC OFFS -0.1',...
            'enable','off');
        
        DCOFFS_less1=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 40 80 20],'string','-1',...
            'callback',@newSRS,'tag','DC OFFS -1',...
            'enable','off');
        
        DCOFFS_less10=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 10 80 20],'string','-10',...
            'callback',@newSRS,'tag','DC OFFS -10',...
            'enable','off');
        
        %% AC freq
        
        ACFREQlabel=uicontrol(microscope_window_handle,'style','text',...
            'string','AC FREQ',...
            'Position',[650 195 100 20]);
        
        ACFREQ=uicontrol(microscope_window_handle,'style','text',...
            'string','??? Hz','position',[650 180 100 20]);
        
        ACFREQ_plus10=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 160 80 20],'string','+10',...
            'callback',@newSRS,'tag','AC FREQ +10',...
            'enable','off');
        
        ACFREQ_plus1=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 130 80 20],'string','+1',...
            'callback',@newSRS,'tag','AC FREQ +1',...
            'enable','off');
        
        ACFREQ_plus01=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 100 80 20],'string','+0.1',...
            'callback',@newSRS,'tag','AC FREQ +0.1',...
            'enable','off');
        
        ACFREQ_less01=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 70 80 20],'string','-0.1',...
            'callback',@newSRS,'tag','AC FREQ -0.1',...
            'enable','off');
        
        ACFREQ_less1=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 40 80 20],'string','-1',...
            'callback',@newSRS,'tag','AC FREQ -1',...
            'enable','off');
        
        ACFREQ_less10=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 10 80 20],'string','-10',...
            'callback',@newSRS,'tag','AC FREQ -10',...
            'enable','off');
        
        %% AC AMP
        ACAMPlabel=uicontrol(microscope_window_handle,'style','text',...
            'string','AC AMP',...
            'Position',[750 195 100 20]);
        
        ACAMP=uicontrol(microscope_window_handle,'style','text',...
            'string','??? VP','position',[750 180 100 20]);
        
        %         ACAMP_plus10=uicontrol(microscope_window_handle,'style','pushbutton',...
        %             'position',[750 160 80 20],'string','+10',...
        %             'callback',{@newSRS,ACAMP},'tag','AC AMP  +10',...
        %             'enable','off');
        
        %         ACAMP_plus1=uicontrol(microscope_window_handle,'style','pushbutton',...
        %             'position',[750 130 80 20],'string','+1',...
        %             'callback',{@newSRS,ACAMP},'tag','AC AMP  +1');
        
        ACAMP_plus01=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[750 100 80 20],'string','+0.1',...
            'callback',{@newSRS,ACAMP},'tag','AC AMP  +0.1',...
            'enable','off');
        
        ACAMP_less01=uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[750 70 80 20],'string','-0.1',...
            'callback',{@newSRS,ACAMP},'tag','AC AMP  -0.1',...
            'enable','off');
        
        %         ACAMP_less1=uicontrol(microscope_window_handle,'style','pushbutton',...
        %             'position',[750 40 80 20],'string','-1',...
        %             'callback',{@newSRS,ACAMP},'tag','AC AMP  -1');
        
        %         ACAMP_less10=uicontrol(microscope_window_handle,'style','pushbutton',...
        %             'position',[750 10 80 20],'string','-10',...
        %             'callback',{@newSRS,ACAMP},'tag','AC AMP  -10');
        
        mgain_auto=uicontrol('parent',microscope_window_handle,...
            'style','checkbox','string','Auto Gain',...
            'value',0,'position',[10 250 140 20],...
            'callback',@microscope_auto_gain);
        
    end

    function initialize_microscope_variables(source,eventdata)
        %create shared data for microscope
        temp.microscope_video_handle = videoinput('pointgrey',1,'Mono8_1280x960');
        temp.microscope_video_handle.FramesPerTrigger = 1;
        triggerconfig(temp.microscope_video_handle, 'manual');
        set(temp.microscope_video_handle, 'TriggerRepeat', Inf);
        temp.src_microscope = getselectedsource(temp.microscope_video_handle);
        temp.src_microscope.GainMode = 'Manual';
        setappdata(main,'microscope_video_handle',temp.microscope_video_handle)
        setappdata(main,'microscope_source_data',temp.src_microscope)
        
    end

    function build_fringe_window(source,eventdata)
        fringe_window_handle=figure('visible','off',...
            'Name','fringe',...
            'Position',[800,100,600,300],...
            'MenuBar','none',...
            'ToolBar','none');
        
        set(fringe_window_handle,'visible','on')
        
        %create a button that arms the camera
        farm=uicontrol(fringe_window_handle,'style','togglebutton','String','Run Camera',...
            'Value',0,'position',[10 100 100 20],...
            'Callback',@fringe_camera_arm);
        
        %create a static text box to show camera status
        fstatus_display=uicontrol(fringe_window_handle,'style','text','string','Camera Status',...
            'position',[120 90 50 30]);
        set(fstatus_display,'backgroundcolor',[1 1 0]);
        
        %create slider for gain
        fgain_slider=uicontrol(fringe_window_handle,'style','slider',...
            'min',0,'max',18,'value',2,...
            'sliderstep',[0.01 0.2],...
            'position',[10 70 100 20],...
            'Callback',@change_fringe_gain);
        
        %create a static text to show camera gain
        fgain_display=uicontrol(fringe_window_handle,'style','text',...
            'string',[num2str(get(fgain_slider,'value'),'%2.1f') ' dB'],...
            'position',[120 70 50 15]);
        
        %create slider for shutter
        fshutter_slider=uicontrol(fringe_window_handle,'style','slider',...
            'min',0.011,'max',33.2,'value',1,...
            'sliderstep',[0.001 0.2],...
            'position',[10 40 100 20],...
            'Callback',@change_fringe_shutter);
        
        %create a static text to show camera shutter
        fshutter_display=uicontrol(fringe_window_handle,'style','text',...
            'string',[num2str(get(fgain_slider,'value')) ' ms'],...
            'position',[120 40 50 15],...
            'Callback',@change_fringe_shutter);
        
        ffullscreen_button=uicontrol(fringe_window_handle,'style','pushbutton',...
            'string','Full Screen',...
            'position',[10 10 100 20],...
            'Callback',@fringe_fullscreen);
        
        
            %create a tab group for voltage plot
        tgroup1=uitabgroup('parent',fringe_window_handle,'position',[0.3 0.05 0.6 0.9]);
        tg1t1=uitab('parent',tgroup1,'Title','Fringe Camera');
        tg1t2=uitab('parent',tgroup1,'Title','Fringe Data');
        tg1t3=uitab('parent',tgroup1,'Title','Latest Andor Spectrum');
        
              
        %create the axes for the fringe camera
        ax2=axes('parent',tg1t1);
        set(ax2,'xticklabel',[]);
        set(ax2,'xtick',[]);
        set(ax2,'yticklabel',[]);
        set(ax2,'ytick',[]);
        %set the axes to not reset plot propertes
        set(ax2,'nextplot','add');
        set(ax2,'ydir','reverse');
        set(ax2,'xlim',[0 640],'ylim',[0 480])
        
        set(ax2,'Unit','normalized','Position',[0 0 1 1])
       
        %create the axes for the fringe trend display
        ax22=axes('parent',tg1t2);
        set(ax22,'nextplot','replacechildren');
        set(ax22,'xlimmode','auto')
        
        ax23=axes('parent',tg1t3);
        set(ax23,'nextplot','replacechildren');
        set(ax23,'xlimmode','auto')
        
        fopt_checkbox=uicontrol('parent',fringe_window_handle,'style','checkbox',...
            'string','Optimize fringe pattern',...
            'value',0,'position',[10 125, 140, 20]);
        
        fgain_auto=uicontrol('parent',fringe_window_handle,...
            'style','checkbox','string','Auto Gain',...
            'value',0,'position',[10 150 140 20],...
            'callback',@fringe_auto_gain);
        
        initialize_fringe_variables;
    end

    function fringe_auto_gain(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,fringe_window_handle);
        temp=getappdata(main);
        if(source.Value)
            localhandles(5).Enable='off';
            localhandles(6).Enable='off';
            localhandles(7).Enable='off';
            localhandles(8).Enable='off';
            temp.fringe_source_data.ShutterMode='auto';
            temp.fringe_source_data.GainMode='auto';
            setappdata(main,'fringe_source_data',temp.fringe_source_data);
        else
            localhandles(5).Enable='on';
            localhandles(6).Enable='on';
            localhandles(7).Enable='on';
            localhandles(8).Enable='on';
            temp.fringe_source_data.ShutterMode='manual';
            temp.fringe_source_data.GainMode='manual';
            setappdata(main,'fringe_source_data',temp.fringe_source_data);
        end
    end

    function initialize_fringe_variables(source,eventdata)
        %create shared data for fringe camera
        temp.fringe_video_handle = videoinput('pointgrey',2,'Mono8_1280x960');
        temp.fringe_video_handle.FramesPerTrigger = 1;
        triggerconfig(temp.fringe_video_handle, 'manual');
        set(temp.fringe_video_handle, 'TriggerRepeat', Inf);
        temp.src_fringe = getselectedsource(temp.fringe_video_handle);
        temp.src_fringe.GainMode = 'Manual';
        setappdata(main,'fringe_video_handle',temp.fringe_video_handle)
        setappdata(main,'fringe_source_data',temp.src_fringe)
    end

    function build_arduino_window(source,eventdata)
        arduino_window_handle=figure('visible','off',...
            'Name','Arduino',...%'Position',[250,500,500,300]...
            'MenuBar','none',...
            'ToolBar','none');
        
        set(arduino_window_handle,'visible','on')
        
        inject_pushbutton=uicontrol(arduino_window_handle,'style','pushbutton',...
            'String','Inject','position',[250 10 75 20],...
            'callback',@inject,'enable','off');
        
        burst_pushbutton=uicontrol(arduino_window_handle,'style','pushbutton',...
            'String','Burst','position',[250 35 75 20],...
            'callback',@burst,'enable','off');
        
        inject_display=uicontrol(arduino_window_handle,'style','text',...
            'string','0','position',[325 10 150 20]);
        
        %check which serial ports are available
        serialinfo=instrhwinfo('serial');
        arduino_selectbox=uicontrol(arduino_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[10 10 100 20]);
        
        arduino_openclose=uicontrol(arduino_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[120 10 100 20],...
            'callback',@arduinocomms,'tag','arduino');
        
        bgarduino = uibuttongroup(arduino_window_handle,'Position',[0 0.1 .5 .15],...
            'title','Sensor Select','SelectionChangeFcn',@arduino_mode);
        
        % Create three radio buttons in the button group.
        arduino_r1 = uicontrol(bgarduino,'Style',...
            'radiobutton',...
            'String','1',...
            'Position',[10 10 30 20],...
            'HandleVisibility','off','enable','on');
        
        arduino_r2 = uicontrol(bgarduino,'Style','radiobutton',...
            'String','2',...
            'Position',[50 10 30 20],...
            'HandleVisibility','off','enable','on');
        
        ardiuno_r3 = uicontrol(bgarduino,'Style','radiobutton',...
            'String','3',...
            'Position',[90 10 30 20],...
            'HandleVisibility','off','enable','off');
        
        ax20=axes('parent',arduino_window_handle,'position',[0.15 0.35 0.8 0.25]);
        set(ax20,'nextplot','replacechildren');
        set(ax20,'xtickmode','auto')
        set(ax20,'xlimmode','auto')
        
        ax21=axes('parent',arduino_window_handle,'position',[0.15 0.7 0.8 0.25]);
        set(ax21,'nextplot','replacechildren');
        set(ax21,'xtickmode','auto')
        set(ax21,'xlimmode','auto')
        set(ax21,'xtick',[])
        
        linkaxes([ax20 ax21],'x')
    end

    function build_MKS_window(source,eventdata)
        MKS_window_handle=figure('visible','off',...
            'Name','MKS',...
            'Position',[50,100,700,300],...
            'MenuBar','none',...
            'ToolBar','none');
        
        set(MKS_window_handle,'visible','on')
        
        %check which serial ports are available
        %        roomTbox=uicontrol(MKS_window_handle,'style','edit',...
        %            'string','20','position',[250 220 50 20]);
        
        serialinfo=instrhwinfo('serial');
        
        Lauda_T_controlbutton=uicontrol(MKS_window_handle,'style','togglebutton',...
            'position',[360 225 100 20],'String','Control ?','callback',@LaudaControl,...
            'enable','off');
        
        
        Lauda_chiller_on_off=uicontrol(MKS_window_handle,'style','togglebutton',...
            'position',[470 225 100 20],'String','Chiller ?','callback',@LaudaChiller,...
            'enable','off');
        
        Julaboselectbox=uicontrol(MKS_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[10 200 100 20]);
        
        Julaboopenclose=uicontrol(MKS_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[120 200 100 20],...
            'callback',@Julabocomms);
        
        Julabo_on_off=uicontrol(MKS_window_handle,'style','togglebutton',...
            'position',[230 200 100 20],'String','Pump ?','callback',@JulaboPower,...
            'enable','off');
        
        Julabo_set_T=uicontrol(MKS_window_handle,'style','edit',...
            'position',[340 200 100 20],'String','T: ?',...
            'callback',@Julabo_send_T,'enable','off');
        
        Julabo_reported_T=uicontrol(MKS_window_handle,'style','text',...
            'position',[450 200 100 20],'String','T: ?');
        
        MKSselectbox=uicontrol(MKS_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[10 250 100 20]);
        
        MKSopenclose=uicontrol(MKS_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[120 250 100 20],...
            'callback',@MKScomms);
        
        Laudaselectbox=uicontrol(MKS_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[240 250 100 20]);
        
        Laudaopenclose=uicontrol(MKS_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[360 250 100 20],...
            'callback',@Laudacomms);
        
        
        MKScommandpre=uicontrol(MKS_window_handle,'style','text',...
            'string','@253','position',[10 195 50 20],'visible','off');
        
        MKScommandpost=uicontrol(MKS_window_handle,'style','text',...
            'string',';FF','position',[150 195 50 20],'visible','off');
        
        MKScommandline=uicontrol(MKS_window_handle,'style','edit',...
            'position',[50 195 110 20],'visible','off');
        
        MKSsendbutton=uicontrol(MKS_window_handle,'style','pushbutton',...
            'position',[210 195 50 20],'string','send',...
            'enable','off','callback',@MKSsend,'visible','off');
        
        MKSresponse=uicontrol(MKS_window_handle,'style','text',...
            'position',[10 170 250 20],'string','Response:','visible','off');
        
        
        bg3 = uibuttongroup(MKS_window_handle,'Position',[0 0.05 .15 .5],...
            'title','Dry CH3','SelectionChangeFcn',@MKS_mode,'tag','3');
        
        % Create three radio buttons in the button group.
        mks3_r1 = uicontrol(bg3,'Style',...
            'radiobutton',...
            'String','Open',...
            'Position',[10 80 65 20],...
            'HandleVisibility','on','enable','on');
        
        mks3_r2 = uicontrol(bg3,'Style','radiobutton',...
            'String','Close',...
            'Position',[10 60 65 20],...
            'HandleVisibility','on','enable','on');
        
        mks3_r3 = uicontrol(bg3,'Style','radiobutton',...
            'String','Setpoint',...
            'Position',[10 40 65 20],...
            'HandleVisibility','on','enable','on');
        
        mks3sp = uicontrol(bg3,'style','edit',...
            'position',[10 10 65 20],...
            'callback',{@MKSchangeflow,3,NaN},'enable','off','tag','3');
        
        
        
        mks3act = uicontrol(bg3,'style','text',...
            'position',[10 95 65 20],'string','? sccm');
        
        bg4 = uibuttongroup(MKS_window_handle,'Position',[0.17 0.05 .15 .5],...
            'title','Humid CH4','SelectionChangeFcn',@MKS_mode,'tag','4');
        
        % Create three radio buttons in the button group.
        mks4_r1 = uicontrol(bg4,'Style',...
            'radiobutton',...
            'String','Open',...
            'Position',[10 80 65 20],...
            'HandleVisibility','on','enable','on');
        
        mks4_r2 = uicontrol(bg4,'Style','radiobutton',...
            'String','Close',...
            'Position',[10 60 65 20],...
            'HandleVisibility','on','enable','on');
        
        mks4_r3 = uicontrol(bg4,'Style','radiobutton',...
            'String','Setpoint',...
            'Position',[10 40 65 20],...
            'HandleVisibility','on','enable','on');
        
        mks4sp = uicontrol(bg4,'style','edit',...
            'position',[10 10 65 20],...
            'callback',{@MKSchangeflow,4,NaN},'enable','off','tag','4');
        
        mks4act = uicontrol(bg4,'style','text',...
            'position',[10 95 65 20],'string','? sccm');
        
        hum_table = uitable(MKS_window_handle,'Data',[0 -999 -999 -999 -999],'ColumnWidth',{77},...
            'ColumnEditable', [true true true true true],...
            'position',[250 10 440 150],'ColumnName',{'Time (Hr)','Trap (�C)','RH (%)','Total (sccm)','Hookah (�C)'},...
            'celleditcallback',@edit_table);
        
        addrow_button = uicontrol(MKS_window_handle,'style','pushbutton','string','+1 row',...
            'position',[325 170 75 20],...
            'callback',@addrow_fcn);
        
        simulate_ramp = uicontrol(MKS_window_handle,'style','pushbutton','string','Simulate',...
            'position',[405 170 75 20],...
            'callback',@sim_ramp_fcn);
        
        cleartable_button = uicontrol(MKS_window_handle,'style','pushbutton','string','clear',...
            'position',[485 170 75 20],...
            'callback',@cleartable_fcn);
        
        runramp_button=uicontrol(MKS_window_handle,'style','togglebutton','string','Ramp Trap',...
            'position',[565 170 75 20],...
            'callback',@drive_ramps_fcn);
        
        ramp_text=uicontrol(MKS_window_handle,'style','text','string','Ramp Not Running',...
            'position',[525 200 125 20]);
        
        Lauda_on_off=uicontrol(MKS_window_handle,'style','togglebutton',...
            'position',[470 250 100 20],'String','Pump ?','callback',@LaudaPower,...
            'enable','off');
        
        Lauda_set_T=uicontrol(MKS_window_handle,'style','edit',...
            'position',[575 250 100 20],'String','T: ?',...
            'callback',@Lauda_send_T,'enable','off');
        
        Lauda_reported_T=uicontrol(MKS_window_handle,'style','text',...
            'position',[575 220 100 20],'String','T: ?');
        
    end

    function build_Andor_window(source,eventdata)
        Andor_window_handle=figure('visible','off',...
            'Name','Andor',...%'Position',[1500,100,700,700],...
            'MenuBar','none',...
            'ToolBar','none');
        
        set(Andor_window_handle,'visible','on')
        
        andor_abort=uicontrol('parent',Andor_window_handle,'style','pushbutton',...
            'position',[300 225 100 20],'string','Abort Acquisition',...
            'callback',@andor_abort_sub);
        
        acoolerinit=uicontrol('parent',Andor_window_handle,'style','pushbutton',...
            'position',[10 225 100 20],'string','Connect to Andor',...
            'callback',@andor_initalize);
        
        acoolerdisconnect=uicontrol('parent',Andor_window_handle,'style','pushbutton',...
            'position',[120 225 100 20],'string','Disconnect Andor',...
            'callback',@andor_disconnect);
        
        acooler=uicontrol('parent',Andor_window_handle,'style','togglebutton',...
            'value',0,'position',[10 20 100 20],'string','Cooler OFF',...
            'callback',@andor_chiller_power);
        
        acoolerset=uicontrol('parent',Andor_window_handle,'style','edit',...
            'position', [120 20 100 20],'string','-60',...
            'callback',@andor_set_chiller_temp);
        
        acoolersettext=uicontrol('parent',Andor_window_handle,'style','text',...
            'position', [220 20 50 20],'string','?�C');
        
        acooleractualtext=uicontrol('parent',Andor_window_handle,'style','text',...
            'position', [270 20 50 20],'string','?�C');
        
        aaqdata=uicontrol('parent',Andor_window_handle,'style','pushbutton',...
            'string','Get data','position',[10 200 100 20],...
            'callback',@andor_aqdata,'enable','off');
        
        astatus_selectbox=uicontrol(Andor_window_handle,'style','popupmenu',...
            'String',{'Single Scan','Kinetic Series'},...
            'position',[120 200 100 20],...
            'callback',@change_andor_acquisition);
        
        aloop_scan=uicontrol(Andor_window_handle,'style','checkbox',...
            'String','Andor Realtime',...
            'position',[250 200 125 20],...
            'callback',@Andor_Realtime,'enable','off');
        
        a_integrationtime=uicontrol(Andor_window_handle,'style','edit',...
            'string','15','position',[130 170 100 20],...
            'Callback',@change_andor_exposure_time);
        
        a_integrationtime_lab=uicontrol(Andor_window_handle,'style','text',...
            'string','Integration time:','position',[10 170 120 20]);
        
        a_numkinseries=uicontrol(Andor_window_handle,'style','edit',...
            'string','5','position',[130 140 100 20],...
            'Callback',@change_andor_kinetic_length);
        
        a_numkinseries_lab=uicontrol(Andor_window_handle,'style','text',...
            'string','Kinetic series length:','position',[10 140 120 20]);
        
        a_kincyctime=uicontrol(Andor_window_handle,'style','edit',...
            'string','30','position',[130 110 100 20],...
            'Callback',@change_andor_kinetic_time);
        
        a_kincyctime_lab=uicontrol(Andor_window_handle,'style','text',...
            'string','Kinetic cycle time:','position',[10 110 120 20]);
        
        %%
        a_textreadout=uicontrol(Andor_window_handle,'style','text',...
            'string',{'Andor Communications Display Here'},'max',2,'backgroundcolor',[0.7 0.7 0.7],...
            'position',[275 40 200 150]);
        
        %make the spectrometer axes
        ax11=axes('parent',Andor_window_handle,'position',[.1 .55 .8 .4]);
        set(ax11,'nextplot','replacechildren');
        %ylabel(ax11,'Pixel Number')
        %xlabel(ax11,'Time')
        colormap(ax11,'jet')
        set(ax11,'xlimmode','auto')
        
        %make a button to clear the spectrometer figure
        ax11clear=uicontrol(main,'style','pushbutton','string','cla(ax11)',...
            'position',[600 625 75 20],...
            'callback',{@clearaplot,ax11});
        
        grating_selectbox=uicontrol(Andor_window_handle,'style','popupmenu',...
            'String',{'Grating 1 600 lines / mm','Grating 2 1200 lines / mm'},...
            'position',[500 200 100 20],...
            'callback',@change_andor_grating,'enable','off');
        
        wavelengths={'400 nm';'450 nm';...
            '500 nm';'550 nm';...
            '600 nm';'650 nm';...
            '700 nm';'750 nm';...
            '800 nm';'850 nm';...
            '900 nm';'950 nm'};
        
        center_wavelength_selectbox=uicontrol(Andor_window_handle,'style','popupmenu',...
            'String',wavelengths,...
            'position',[500 150 100 20],...
            'callback',@change_andor_wavelength,'enable','off');
        
    end

    function build_hygrometer_window(source,eventdata)
        
        hygrometer_window_handle=figure('visible','off',...
            'Name','Hygrometer',...%'Position',[2250,100,600,300],...
            'MenuBar','none',...
            'ToolBar','none');
        
        hygrometer_display = uicontrol(hygrometer_window_handle,'style','text',...
            'position',[250 10 300 20],'string','Hygrometer reading: ?');
        
        set(hygrometer_window_handle,'visible','on')
        
        %check which serial ports are available
        serialinfo=instrhwinfo('serial');
        hygrometer_selectbox=uicontrol(hygrometer_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[10 10 100 20]);
        
        hygrometer_openclose=uicontrol(hygrometer_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[120 10 100 20],...
            'callback',@hygrometer_comms,'tag','hygrometer');
        
        ax20=axes('parent',hygrometer_window_handle,'position',[0.15 0.25 0.8 0.7]);
        set(ax20,'nextplot','replacechildren');
        set(ax20,'xtickmode','auto')
        set(ax20,'xlimmode','auto')
        
        
    end

%% functions that actually do stuff for main program
    function fasttimer_startstop(source,eventdata)
        if(get(source,'value'))
            start(fasttimer)
            set(source,'string','Stop background timer')
        else
            stop(fasttimer)
            set(source,'string','Start background timer')
        end
        
    end

    function errortimer_startstop(source,eventdata)
        if(get(source,'value'))
            start(errorcatchtimer)
            set(source,'string','Stop error catch timer')
        else
            stop(errorcatchtimer)
            set(source,'string','Start error catch timer')
        end
        
    end

    function fasttimerFcn(source,eventdata)
        
        fastloop=tic;
        temp=getappdata(main);
        
        %make default value
        feedbackOK=0;
        
        FrameNumber=mod(temp.FrameNumber+1,1000); %change this one to update SLOW speed
        %updatelogic=mod(FrameNumber,floor(get(fasttimer_slider,'value')))==0; %update every other frame
        updatelogic=mod(FrameNumber,5)==0; %update every fifth frame
        savelogic=(mod(FrameNumber,100)==0); %update about every 100 sec
        datalogic=(mod(FrameNumber,50)==0); %update about every 10 s
        %check if any connected hardware needs to be started or stopped
        
        %disp(FrameNumber)
        
        if(~isempty(ishandle(microscope_window_handle))&&~isempty(ishandle(fringe_window_handle)))
            [feedbackOK,fringe_compressed,fringe_image,microscope_image]=update_cameras(source,eventdata,temp,updatelogic,datalogic);
        end
        
        fasttime=toc(fastloop);
        set(fastupdatetext,'string',['Fast update: ' num2str(fasttime) ' s']);
        setappdata(main,'FrameNumber',FrameNumber)
        
        % remainder of fasttimerFcn only runs when `datalogic` true
        if(datalogic)
            stop(fasttimer)
            if(exist('fringe_compressed','var')&&~isempty(fringe_compressed))
                if(savelogic)
                    if(~isa(temp.fringe_compressed,'uint8'))
                        temp.fringe_compressed=uint8(temp.fringe_compressed);
                    end
                    temp.fringe_compressed(end+1,:)=uint8(fringe_compressed);
                    %disp(FrameNumber)
                    temp.fringe_timestamp(end+1)=now;
                    setappdata(main,'fringe_compressed',temp.fringe_compressed);
                    setappdata(main,'fringe_timestamp',temp.fringe_timestamp);
                    if(mod(size(temp.fringe_compressed,1),20)==1)
                        temp.image_timestamp(end+1)=now;
                        setappdata(main,'image_timestamp',temp.image_timestamp);
                        if(~isa(temp.fringe_image,'uint8'))
                            temp.fringe_image=uint8(temp.fringe_image);
                        end
                        temp.fringe_image(end+1,:,:)=uint8(fringe_image);
                        setappdata(main,'fringe_image',temp.fringe_image);
                        if(~isa(temp.microscope_image,'uint8'))
                            temp.microscope_image=uint8(temp.microscope_image);
                        end
                        temp.microscope_image(end+1,:,:)=uint8(microscope_image);
                        setappdata(main,'microscope_image',temp.microscope_image);
                    end
                end
            end
            if(isfield(temp,'MKS946_comm'))
                update_MKS_values(source,eventdata,savelogic);
            end
            if(isfield(temp,'LaudaRS232'))
                update_Lauda(source,eventdata,savelogic);
            end
            if(isfield(temp,'JulaboRS232'))
                update_Julabo(source,eventdata,savelogic);
            end
            if(isfield(temp,'arduino_comm')&&savelogic)
                update_arduino(source,eventdata,savelogic);
            end
            if(isfield(temp,'Hygrometer_comms')&&datalogic)
                update_hygrometer_data(source,eventdata,datalogic)
%                 if(FrameNumber==0&rand(1)<0.25)
%                     force_hygrometer_heat(source,eventdata)
%                 end
                %if it has been hot for at least 10 minutes, send it back
                %to regular mode
                if(temp.hygrometer_data(find(temp.hygrometer_data(:,1)>(now-15/60/24),1,'first'),2)>90)
                   force_hygrometer_normal(source,eventdata) 
                end
                if((temp.hygrometer_data(end,2)-temp.hygrometer_data(end,3))<-20)
                    %force_hygrometer_heat(source,eventdata)
                end
            end
            if(temp.AndorFlag)
                update_Andor_values(source,eventdata);
                get_andor_data(source,eventdata);
            end
            if(feedbackOK)
                plothandle=get_figure_handles(source,eventdata,microscope_window_handle);
                voltage_plothandle=plothandle(end-7).Children(2).Children(1);
                microscopehandles=get_figure_handles(source,eventdata,microscope_window_handle);
                temp=getappdata(main);
                if(~isempty(str2num(microscopehandles(end-20).String(1:end-3)))&microscopehandles(end-11).Value)
                    temp.VoltageData(end+1,:)=[now str2num(microscopehandles(end-20).String(1:end-3))];
                    setappdata(main,'VoltageData',temp.VoltageData)
                else
                    temp.voltage_data_nofeedback(end+1,:)=[now str2num(microscopehandles(end-20).String(1:end-3))];
                    setappdata(main,'voltage_data_nofeedback',temp.voltage_data_nofeedback);
                end
                if(size(temp.VoltageData,1)>1&&strcmp(microscopehandles(end-7).SelectedTab.Title,'Voltage Plot'))
                    cla(voltage_plothandle);
                    voltage_plothandle.XLimMode='Auto';
                    voltage_plothandle.XTickMode='Auto';
                    voltage_plothandle.XTickLabelMode='Auto';
                    plot(voltage_plothandle,temp.VoltageData(:,1),temp.VoltageData(:,2).*1000,'.');
                    if(size(temp.voltage_data_nofeedback,1)>1)
                       hold(voltage_plothandle,'on');
                       plot(voltage_plothandle,temp.voltage_data_nofeedback(:,1),temp.voltage_data_nofeedback(:,2).*1000,'o')
                    end
                    ylabel(voltage_plothandle,'V DC (V)')
                    datetick(voltage_plothandle,'x','(DD).HH','keepticks')
                    xlabel(voltage_plothandle,'Time (DD).HH')
                else
                    cla(voltage_plothandle);
                end
                

            end
            
            andor_localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
            fringe_localhandles=get_figure_handles(source,eventdata,fringe_window_handle);
            set(fringe_localhandles(3).Children(3).Children(1),'ydir','normal');
            update_andor_plot_1D(source,eventdata,fringe_localhandles(3).Children(3).Children(1))
            if(temp.AndorFlag&&andor_localhandles(11).Value==1)
                %update Andor plot
                update_andor_plot_1D(source,eventdata,andor_localhandles(end));
%                 if(andor_localhandles(10).Value&(size(temp.AndorImage,2)==(temp.AndorImage_startpointer+1)))
%                     %strip out most recent spectrum so it doesn't get saved
%                     temp.AndorImage(:,end)=[];
%                     setappdata(main,'AndorImage',temp.AndorImage)
%                 end
            elseif(temp.AndorFlag&&andor_localhandles(11).Value==2)
                update_andor_plot_2D(source,eventdata);
            end
            
            if(temp.RampFlag)
                dt=(now-temp.RampTime_init)*24;
                localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
                if(dt>temp.Ramp_data(end,1))
                    %the ramp is over
                    localhandles(5).Value=0;
                    %localhandles(5).String='Ramp';
                    %localhandles(4).String='Ramp not running';
                    set(localhandles(9),'enable','on')
                    setappdata(main,'RampFlag',0)
                    set(localhandles(5),'string','Ramp Trap')
                else
                    localhandles(4).String=['Ramp: ' num2str(dt,'%2.1f') ' of ' num2str(temp.Ramp_data(end,1),'%2.1f') ' hrs'];
                    flow1=min([interp1(temp.Ramp_data(:,1),temp.Ramp_data(:,2),dt,'linear') 200]);
                    flow2=min([interp1(temp.Ramp_data(:,1),temp.Ramp_data(:,3),dt,'linear') 200]);
                    T=interp1(temp.Ramp_data(:,1),temp.Ramp_data(:,4),dt,'linear');
                    JulaboT=interp1(temp.Ramp_data(:,1),temp.Ramp_data(:,5),dt,'linear');
                    %ensure flow controllers are turned on if flow ~= 0
                    if(flow1>=4) %dry
                        %make sure MFC is turned to SETPOINT
                        MKSsend(source,eventdata,'QMD3!SETPOINT');
                        MKSchangeflow(source,eventdata,3,flow1);
                        localhandles(11).Children(2).String=flow1;
                    elseif(flow1<4)
                        %turn MFC to CLOSE
                        MKSsend(source,eventdata,'QMD3!CLOSE');
                        localhandles(11).Children(2).String='CLOSED';
                    end
                    if(flow2>=4) %humid
                        %make sure MFC is turned to SETPOINT
                        MKSsend(source,eventdata,'QMD4!SETPOINT');
                        MKSchangeflow(source,eventdata,4,flow2);
                        localhandles(10).Children(2).String=flow2;
                    elseif(flow2<4)
                        %turn MFC to CLOSE
                        MKSsend(source,eventdata,'QMD4!CLOSE');
                        localhandles(10).Children(2).String='CLOSED';
                    end
                    
                    Lauda_send_T(source,eventdata,T);
                    update_Lauda(source,eventdata,savelogic);
                    Julabo_send_T(source,eventdata,JulaboT);
                    update_Julabo(source,eventdata,savelogic);
                end
            end
            
            %update fringe data tab
            flocalhandles=get_figure_handles(source,eventdata,fringe_window_handle);
            if(size(temp.fringe_compressed,1)>1&...
                    strcmp(flocalhandles(3).SelectedTab.Title,...
                    'Fringe Data'))
                
                peaksep=ACBAR_realtime_fringe_analysis(source,eventdata,temp);
                
                cla(flocalhandles(3).Children(2).Children(1));
                
                errorbar(flocalhandles(3).Children(2).Children(1),...
                    temp.fringe_timestamp,peaksep(:,1),peaksep(:,2));
                
                flocalhandles(3).Children(2).Children(1).XLimMode='auto';
                flocalhandles(3).Children(2).Children(1).XTickMode='auto';
                
                datetick(flocalhandles(3).Children(2).Children(1),...
                    'x','DD.HH')
                xlabel(flocalhandles(3).Children(2).Children(1),'Time (DD.HH)')
                ylabel(flocalhandles(3).Children(2).Children(1),'Peak Separation (px)')
                
            end
            
            set(slowupdatetext,'string',['Slow: ' datestr(now)])
            
            if(save_checkbox.Value&FrameNumber==0)
                eval(['save ' save_filename.String ' temp -v7.3'])
            end
            start(fasttimer)
        end
        
    end

    function [peaksep]=ACBAR_realtime_fringe_analysis(source,eventdata,temp)
        %try putting plots in time order like the LED spectra are
        X=temp.fringe_timestamp;
        nday=mean(diff(X)); %use the average spacing
        %nday=n/60/24; %convert to days
        newX=X(1):nday:X(size(temp.fringe_compressed,1));
        newX_coordinates=interp1(X,1:size(X,2),newX);
        new_1Dfringe=temp.fringe_compressed(round(newX_coordinates),:);
        
        
        
        dX=diff(newX_coordinates);
        %find identical data
        gaps=find(dX<0.999);
        
        for i=2:length(gaps)
            if(gaps(i)==(gaps(i-1)+1)) %if gaps are sequential
                new_1Dfringe(gaps(i),:)=NaN;
            end
        end
        
        new_1Dfringe=double(new_1Dfringe);
        %allow for plotting if desired
        if(0)
            im1=image(new_1Dfringe');
            ax1=gca;
            set(im1,'cdatamapping','scaled')
            set(im1,'XData',[newX(1) newX(end)])
            set(ax1,'XLim',[newX(1) newX(end)])
            
            %convert new_1Dfringe to double to matlab work on it
            
            
            onedpcts=prctile(new_1Dfringe,[10 90]);
            lowerlimit=min(onedpcts(1,onedpcts(1,:)~=0));
            upperlimit=max(onedpcts(2,onedpcts(1,:)~=0));
            %upperlimit=1500;
            caxis([lowerlimit upperlimit])
            ylabel('Pixel Number');
            xlabel('Time (DD HH)')
            datetick('x','DD HH')
        end
        
        
        
        %preallocate for 30 peaks at most
        peakheights=zeros(size(new_1Dfringe,1),30);
        peaklocs=zeros(size(new_1Dfringe,1),30);
        offset=15;
        diffpeaklocs=[];
        h=waitbar(0,['Fringe peak analysis...']);
        for i=1:size(new_1Dfringe,1)
            [p,l]=findpeaks(smooth(new_1Dfringe(i,offset:end-offset)),'MinPeakDistance',10);
            peakheights(i,1:length(p))=p;
            peaklocs(i,1:length(l))=l;
            %plot(1:480,smooth(new_1Dfringe(i,:)),peaklocs(i,:)+offset,peakheights(i,:),'x')
            % pause
            diffpeaklocs=diff(peaklocs);
            if(mod(i,10)==0)
                waitbar(i/size(new_1Dfringe,1),h)
            end
        end
        close(h)
        
        %find the average and std of difference in peak location, up to the
        %negative one that indicates it is not a peak
        diffpeaklocs=diff(peaklocs,1,2);
        for i=1:size(diffpeaklocs,1)
            maxinx=find(diffpeaklocs(i,:)>0,1,'last');
            peaksep(i,:)=[mean(diffpeaklocs(i,1:maxinx)) std(diffpeaklocs(i,1:maxinx))];
        end
        
        clear ax1 h i im1 l lowerlimit maxinx n nday p upperlimit diffpeaklocs
        
        
        
        %perform 20 minute bin averages weighted by error
        %using the equation at end of
        %http://www.physics.umd.edu/courses/Phys261/F06/ErrorPropagation.pdf
%         newX_bins=newX(1):10/60/24:newX(end);
%         within=@(D,ti,tf)D>=ti&D<tf;
%         fringe_data=[];
%         for i=1:length(newX_bins)-1
%             wkind=find(within(newX,newX_bins(i),newX_bins(i+1)));
%             time=mean(newX(wkind));
%             newvalue=sum(peaksep(wkind,1)./peaksep(wkind,2).^2)./sum(1./peaksep(wkind,2).^2);
%             newerror=sqrt(sum(1./peaksep(wkind,2).^2));
%             fringe_data(end+1,:)=[time newvalue newerror];
%         end
        
        
        

    end
        



    function errorcatchFcn(source,eventdata)
        wasrunning=strcmp(get(fasttimer,'running'),'on');
        if(wasrunning)
            stop(fasttimer)
            pause(0.25)
        end
        %check to see if the timer button is pushed, but timer not running
        if(~wasrunning&&get(fasttimer_button,'value'))
            disp(['Auto restart fast timer at ' datestr(now)])
            beep;
            start(fasttimer)
        elseif(wasrunning&&get(fasttimer_button,'value'))
            %everything is fine, restart the timer
            disp('Everything is fine with the error catch timer')
            start(fasttimer)
        end
    end

    function microscope_checkbox_fcn(source,eventdata)
        if(get(source,'value'))
            setappdata(main,'microscope_subVI',1)
        else
            setappdata(main,'microscope_subVI',0)
        end
    end

    function fringe_checkbox_fcn(source,eventdata)
        if(get(source,'value'))
            setappdata(main,'fringe_subVI',1)
        else
            setappdata(main,'fringe_subVI',0)
        end
    end

    function SCRAM_COMMS(source,eventdata)
        %delete all COMs
        delete(instrfindall)
        %repoll and refresh list of COMs
        serialinfo=instrhwinfo('serial');
        %set(MKSselectbox,'enable','on');
        %set(MKSopenclose,'string','Port Closed','Value',0);
        %set(MKSsendbutton,'enable','off');
        %set(MKSflushbutton,'enable','off');
        localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
        set(localhandles(22),'String',serialinfo.AvailableSerialPorts);
        set(localhandles(21),'value',0,'string','Port Closed')
        set(localhandles(25),'String',serialinfo.AvailableSerialPorts);
        set(localhandles(24),'value',0,'string','Port Closed')
        if(ishandle(arduino_window_handle))
            localhandles=get_figure_handles(source,eventdata,arduino_window_handle);
            set(localhandles(3),'String',serialinfo.AvailableSerialPorts);
            set(localhandles(2),'value',0,'string','Port Closed')
        end
        if(ishandle(MKS_window_handle))
            localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
            set(localhandles(20),'String',serialinfo.AvailableSerialPorts);
            set(localhandles(19),'value',0,'string','Port Closed')
            set(localhandles(18),'String',serialinfo.AvailableSerialPorts);
            set(localhandles(17),'value',0,'string','Port Closed')
        end
        
    end

    function Flush_data(source,eventdata)
        stop(fasttimer)
        temp=getappdata(main);
        choice = questdlg('This will clear all data in program memory. Are you sure?', ...
            'Yes','No');
        %TO DO: save all data before clearing in case it hasn't been saved
        %recently!
        if(strcmp(choice,'Yes'))
            if(save_checkbox.Value)
                eval(['save ' save_filename.String ' temp -v7.3'])
                
            end
            
            %turn off save checkbox
            set(save_checkbox,'value',0);
            %reset filename
            set(save_filename,'string','Enter new file name');
            listofnames=fieldnames(temp);
            namestokeep={'microscope_video_handle';'microscope_source_data';...
                'fringe_video_handle';'fringe_source_data';...
                'IdealY';'RampFlag';'AndorCalPoly';'AndorFlag';...
                'UPSInumber';'microscope_subVI';'fringe_subVI';...
                'camera1Flag';'camera2Flag';'FrameNumber';'UPSInumber';'ShamrockGrating';...
                'ShamrockXCal';'MKS946_comm';'LaudaRS232';'DS345_DC';'DS345_AC';...
                'arduino_comm';'JulaboRS232';'Hygrometer_comms'};
            for i=1:length(listofnames)
                if(~ismember(listofnames{i},namestokeep))
                    eval(['setappdata(main,''' listofnames{i} ''',[])'])
                end
            end
        end
        
        
        start(fasttimer)
    end



%% functions that actually do stuff for all subprograms
    function localhandles=get_figure_handles(source,eventdata,handlein)
        localhandles=get(handlein,'children');
    end

    function wait_a_second(source,eventdata,handlein)
        set(handlein ,'pointer','watch')
    end

    function good_to_go(source,eventdata,handlein)
        set(handlein,'pointer','arrow')
    end

    function clearaplot(source,eventdata,plotpointer)
        cla(plotpointer);
    end

    function [feedbackOK,fringe_compressed,fringe_image,microscope_image]=update_cameras(source,eventdata,temp,updatelogic,datalogic)
        feedbackOK=0; %set a default value
        fringe_compressed=[]; %set a default value
        fringe_image=[];
        microscope_image=[];
        %get video data if running
        camera1running=isrunning(temp.microscope_video_handle);
        camera2running=isrunning(temp.fringe_video_handle);
        if(camera1running&&~camera2running)
            trigger(temp.microscope_video_handle);
            IM1=getdata(temp.microscope_video_handle,1,'uint8');    %get image from camera
            IM1_small=imresize(IM1,[480 640]);
            [~,ycentroid,feedbackOK]=microscope_blob_annotation(source,eventdata,IM1_small,updatelogic);
            [localhandles]=get_figure_handles(source,eventdata,microscope_window_handle);
            if(get(localhandles(2+6+21),'value')&&feedbackOK&&datalogic)
                if(isfield(temp,'PID_oldvalue'))
                    microscope_feedback_hold(source,eventdata,ycentroid);
                else
                    setappdata(main,'PID_oldvalue',ycentroid);
                end
            end
            microscope_image=uint8(IM1_small);
        elseif(camera2running&&updatelogic&&~camera1running)
            trigger(temp.fringe_video_handle);
            IM2=getdata(temp.fringe_video_handle,1,'uint8');
            IM2_small=imresize(IM2,[480 640]);
            [localhandles]=get_figure_handles(source,eventdata,fringe_window_handle);
            %           set(localhandles(9),'ydir','normal');
            %set(main,'CurrentAxes',ax2);
            cla(localhandles(3).Children(1).Children(1))
            imshow(IM2_small,'parent',localhandles(3).Children(1).Children(1))
            str = ['Time: ' datestr(now)];
            xtextloc=225;
            ytextloc=450;
            text(localhandles(3).Children(1).Children(1),double(xtextloc),double(ytextloc),str,'color','white')
            if(get(localhandles(2),'value'))
                [fringe_compressed]=fringe_annotation(source,eventdata,IM2_small);
                fringe_image=IM2_small;
            end
        elseif(camera1running&&camera2running&&updatelogic)
            trigger(temp.microscope_video_handle);
            trigger(temp.fringe_video_handle);
            IM1=getdata(temp.microscope_video_handle,1,'uint8');    %get image from camera
            IM2=getdata(temp.fringe_video_handle,1,'uint8');
            IM1_small=imresize(IM1,[480 640]);
            [~,ycentroid,feedbackOK]=microscope_blob_annotation(source,eventdata,IM1_small,updatelogic);
            [mlocalhandles]=get_figure_handles(source,eventdata,microscope_window_handle);
            if(get(mlocalhandles(2+6+21),'value')&&feedbackOK&&datalogic==1)
                if(isfield(temp,'PID_oldvalue'))
                    microscope_feedback_hold(source,eventdata,ycentroid);
                else
                    setappdata(main,'PID_oldvalue',ycentroid);
                end
            end
            IM2_small=imresize(IM2,[480 640]);
            [flocalhandles]=get_figure_handles(source,eventdata,fringe_window_handle);
            %          set(flocalhandles(9),'ydir','normal');
            cla(flocalhandles(3).Children(1).Children(1))
            imshow(IM2_small,'parent',flocalhandles(3).Children(1).Children(1))
            str = ['Time: ' datestr(now)];
            xtextloc=225;
            ytextloc=450;
            text(flocalhandles(3).Children(1).Children(1),...
                double(xtextloc),double(ytextloc),str,'color','white')
            if(get(flocalhandles(2),'value'))
                [fringe_compressed]=fringe_annotation(source,eventdata,IM2_small);
                fringe_image=IM2_small;
            end
            microscope_image=uint8(IM1_small);
        end
        
        
        %get logical flag for camera1 status
        
        if(~camera1running&&temp.camera1Flag)
            %start the camera feed
            start(temp.microscope_video_handle);
        elseif(camera1running&&~temp.camera1Flag)
            %stop the camera feed
            stop(temp.microscope_video_handle);
        end
        
        %get logical flag for camera2 status
        
        if(~camera2running&&temp.camera2Flag)
            %start the camera feed
            start(temp.fringe_video_handle);
        elseif(camera2running&&~temp.camera2Flag)
            %stop the camera feed
            stop(temp.fringe_video_handle);
        end
    end

%% functions that actually do stuff for microscope camera
    function microscope_fullscreen(source,eventdata)
        temp=getappdata(main);
        preview(temp.microscope_video_handle)
        %beep
        set(source,'value',0)
    end

    function microscope_auto_gain(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
        temp=getappdata(main);
        if(source.Value)
            localhandles(end-2).Enable='off';
            localhandles(end-3).Enable='off';
            localhandles(end-4).Enable='off';
            localhandles(end-5).Enable='off';
            temp.microscope_source_data.ShutterMode='auto';
            temp.microscope_source_data.GainMode='auto';
            setappdata(main,'microscope_source_data',temp.microscope_source_data);
        else
            localhandles(end-2).Enable='on';
            localhandles(end-3).Enable='on';
            localhandles(end-4).Enable='on';
            localhandles(end-5).Enable='on';
            temp.microscope_source_data.ShutterMode='manual';
            temp.microscope_source_data.GainMode='manual';
            setappdata(main,'microscope_source_data',temp.microscope_source_data);
        end
    end

    function microscope_camera_arm(source,eventdata)
        %state of button: 1=on, 0=off
        temp=getappdata(main);
        [localhandles]=get_figure_handles(source,eventdata,microscope_window_handle);
        if(get(source,'value'))
            %turn camera on
            %start(temp.microscope_video_handle);
            setappdata(main,'camera1Flag',1)
            set(localhandles(end-1),'string','Camera Armed');
            set(localhandles(end-1),'backgroundcolor',[0.5 1 0.5]);
            %make gain and shutter control invisible
            set(localhandles(end-4),'visible','off')
            set(localhandles(end-2),'visible','off')
            set(localhandles(end-10),'enable','on')
            set(localhandles(end-6),'visible','off')
        else
            %turn camera off
            setappdata(main,'camera1Flag',0)
            set(localhandles(end-1),'string','Camera Ready');
            set(localhandles(end-1),'backgroundcolor',[1 0.5 0.5]);
            %make gain and shutter controls visible
            set(localhandles(end-4),'visible','on')
            set(localhandles(end-2),'visible','on')
            set(localhandles(end-10),'enable','off')
            set(localhandles(end-6),'visible','on')
            %stop the camera from holding if it is currently holding
            if(get(localhandles(end-11),'value'))
                set(localhandles(end-11),'string','Stopped Holding')
                set(localhandles(end-11),'value',0)
            end
        end
    end

    function change_microscope_gain(source,eventdata)
        %get temporary data and pointers
        temp=getappdata(main);
        [localhandles]=get_figure_handles(source,eventdata,microscope_window_handle);
        %newgain=get(localhandles(10+6),'value');%get the new gain value
        newgain=source.Value;
        %write value to camera
        temp.microscope_source_data.Gain=newgain;
        %write value to indicator
        set(localhandles(end-3),'string',[num2str(newgain,'%10.1f') ' dB'])
        %write source data back to application data
        setappdata(main,'microscope_source_data',temp.microscope_source_data);
        wait_a_second(source,eventdata,microscope_window_handle);
        %update image
        frame=getsnapshot(temp.microscope_video_handle);
        frame_small=imresize(frame,[480 640]);
        good_to_go(source,eventdata,microscope_window_handle);
        imshow(frame_small,'parent',localhandles(end-7).Children(1).Children(1))
    end

    function change_microscope_shutter(source,eventdata)
        %get temporary data and pointers
        temp=getappdata(main);
        [localhandles]=get_figure_handles(source,eventdata,microscope_window_handle);
        %newshutter=get(localhandles(8+6),'value');%get the new gain value
        newshutter=source.Value;
        %write value to camera
        temp.microscope_source_data.Shutter=newshutter;
        %write value to indicator
        set(localhandles(end-5),'string',[num2str(newshutter,'%10.1f') ' ms'])
        %write source data back to application data
        setappdata(main,'microscope_source_data',temp.microscope_source_data);
        wait_a_second(source,eventdata,microscope_window_handle);
        %update image
        frame=getsnapshot(temp.microscope_video_handle);
        frame_small=imresize(frame,[480 640]);
        good_to_go(source,eventdata,microscope_window_handle);
        imshow(frame_small,'parent',localhandles(end-7).Children(1).Children(1))
    end

    function getidealy(source,eventdata)
        stop(fasttimer)
        pause(0.25)
        temp=getappdata(main);
        [localhandles]=get_figure_handles(source,eventdata,microscope_window_handle);
        trigger(temp.microscope_video_handle);
        IM1=getdata(temp.microscope_video_handle);
        IM1_small=imresize(IM1,[480 640]);
        [~,idealy]=microscope_blob_annotation(source,eventdata,IM1_small,0);
        set(localhandles(4+6+20+1),'string',num2str(idealy));
        setappdata(main,'IdealY',idealy);
        start(fasttimer)
    end

    function [x_centroid,y_centroid,feedbackOK]=microscope_blob_annotation(source,eventdata,imdata,plotflag)
        blobtic=tic;
        %attempt fitting
        feedbackOK=1;
        stats=regionprops(im2bw(imdata,0.3));
        sortedstats=sort([stats.Area]);
        [localhandles]=get_figure_handles(source,eventdata,microscope_window_handle);
        if(length(sortedstats)==1)
            %if only one region
            box_ind=find([stats.Area]==sortedstats(end));
        elseif(isempty(sortedstats))
            x_centroid=-999;
            y_centroid=-999;
            feedbackOK=0;
            if(get(localhandles(end-11),'value'))
                set(localhandles(end-11),'string','Stopped Holding')
                %and stop the ramp, if feedback was active
                %note it should be possible to run a ramp with no feedback
                %but turning feedback on and having it turn itself off
                %will stop the ramp
                MKShandles=get_figure_handles(source,eventdata,MKS_window_handle);
                set(MKShandles(9),'enable','on')
                setappdata(main,'RampFlag',0)
                set(MKShandles(5),'string','Ramp Trap')
                set(MKShandles(4),'string','Stopped Ramp')
                set(MKShandles(4),'value',0)
                %and delete the table entries that have already passed
                data=MKShandles(9).Data;
                %for prototyping
                %data(find(MKShandles(9).Data(:,1)<((now-(now-1.25))*24),1,'last'),:)=[];
                %data(2:end,1)=data(2:end,1)-(now-(now-1.25/24))*24
                %the real deal
                %get rid of the points that have already occurred
                temp=getappdata(main);
                data(2:find(MKShandles(9).Data(:,1)<((now-temp.RampTime_init)*24),1,'last'),:)=[];
                %and adjust timestamps to match
                data(2:end,1)=data(2:end,1)-(now-temp.RampTime_init)*24;
                MKShandles(9).Data=data;
                
                
            end
            set(localhandles(end-11),'value',0)
            if(plotflag)
                set(microscope_window_handle,'CurrentAxes',localhandles(end-7).Children(1).Children(1));
                cla(localhandles(end-7).Children(1).Children(1))
                imshow(imdata,'parent',localhandles(end-7).Children(1).Children(1))
                str = ['Time: ' datestr(now)];
                xtextloc=225;
                ytextloc=450;
                text(localhandles(end-7).Children(1).Children(1),double(xtextloc),double(ytextloc),str,'color','white')
            end
            return
        elseif((sortedstats(end-1)/sortedstats(end))>0.3)
            %find the two biggest boxes
            box_ind=find([stats.Area]>=sortedstats(end-1));
        else
            %only one meaningful region
            box_ind=find([stats.Area]==sortedstats(end));
        end
        
        %calculate the centroid
        centroid_data=[stats(box_ind).Centroid];
        y_centroid=mean(centroid_data(2:2:end));
        x_centroid=mean(centroid_data(1:2:end));
        if(plotflag)
            set(microscope_window_handle,'currentaxes',localhandles(end-7).Children(1).Children(1))
            cla(localhandles(end-7).Children(1).Children(1))
            imshow(imdata,'parent',localhandles(end-7).Children(1).Children(1))
            str = ['Time: ' datestr(now)];
            xtextloc=225;
            ytextloc=450;
            text(localhandles(end-7).Children(1).Children(1),double(xtextloc),double(ytextloc),str,'color','white')
            for i=1:length(box_ind)
                rectangle('parent',localhandles(end-7).Children(1).Children(1),'Position', stats(box_ind(i)).BoundingBox,...
                    'EdgeColor','r', 'LineWidth', 1);
            end
            set(microscope_window_handle,'currentaxes',localhandles(end-7).Children(1).Children(1))
            rectangle('parent',localhandles(end-7).Children(1).Children(1),'Position',[x_centroid-20 y_centroid-20 40 40],...
                'Edgecolor','g','LineWidth',1)
        end
        blobtime=toc(blobtic);
    end

    function mholdposition(source,eventdata)
        stop(fasttimer)
        temp=getappdata(main) ;
        if(get(source,'value')&&isfield(temp,'DS345_DC'))
            %            stop(fasttimer)
            set(source,'string','Holding...')
            %ensure that DC offset is in sync with actual voltage
            % set(SRSoffs_inp,'value',str2num(temp.DS345_DC.offset))
            currenttime=clock;
            setappdata(main,'PID_timestamp',currenttime)
            setappdata(main,'PID_Iterm',0);
            setappdata(main,'PID_DCclicktime',currenttime)
            localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
            setappdata(main,'PID_DCvolt',str2num(localhandles(20).String(1:end-3)));
            setappdata(main,'PID_ACfreq',str2num(localhandles(12).String(1:end-3)));
            %            start(fasttimer)
        elseif(get(source,'value')==0&&isfield(temp,'DS345_DC'))
            set(source,'string','Hold Position')
        else
            set(source,'string','Open Comm First')
            set(source,'value',0)
        end
        start(fasttimer)
    end

    function microscope_feedback_hold(source,eventdata,ycentroid)
        fbtic=tic;
        kp=0.000005; %set proportional constant
        ki=0.0000001; %set integral constant
        kd=0.0000001; %set differential constant
        temp=getappdata(main);
        %calculate the general error term
        error=(ycentroid-temp.IdealY);
        %calculate the time change
        currenttime=clock;
        if(isempty(temp.PID_timestamp))
            setappdata(main,'PID_timestamp',currenttime);
            setappdata(main,'PID_Iterm',0);
            return
        end
        dt=etime(currenttime,temp.PID_timestamp);
        localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
        
        SRSoffs_inp=str2num(localhandles(end-20).String(1:end-3));
        if(dt<20)
            %calculate the integrated error term
            Iterm=error*ki*dt+temp.PID_Iterm; %update integral term
            %calculate the derivitive error term
            Dterm=(ycentroid-temp.PID_oldvalue)*kd/dt;
            newY=SRSoffs_inp+error*kp+Iterm+Dterm;
            %disp('PID')
        else
            newY=SRSoffs_inp;%+error*kd;
            Iterm=temp.PID_Iterm; %pass the integrated value without changing it
            %disp('No PID')
        end
        %disp([error*kd Iterm Dterm])
        %         if(newY>=0.0391&&get(SRSoffs_inp,'value')<=0.0390||...
        %                newY<=0.0390&&get(SRSoffs_inp,'value')>=0.0391)
        %            %check to see how long it has been
        %            if(etime(currenttime,temp.PID_DCclicktime)>60)
        %                 setappdata(f,'PID_DCclicktime',currenttime)
        %                 set(SRSoffs_inp,'value',newY)
        %            else
        %                disp(['Too soon! Click-crossing delayed: ' num2str(60-etime(currenttime,temp.PID_DCclicktime))])
        %            end
        %         else
        %to-do: add code to prevent repeated crossing of "click" points in
        %SRS function generator
        
        localhandles(end-20).String(1:end-3)=num2str(newY,'%+07.4f');
        SRSoffs(source,eventdata,newY)
        
        %try to adapt AC voltage as DC changes
        freqfactor=abs(sqrt(1/(newY/temp.PID_DCvolt)));
        newAC=freqfactor*temp.PID_ACfreq;
        newAC=max([100 newAC]); %keep it above 100 Hz
        newAC=min([500 newAC]); %and below 400 Hz
        
        %override new AC frequency if voltage is less than 5 V (it is too
        %agressive in this region as it is based on relative change)
        if(abs(newY<=0.005))
           newAC=temp.PID_ACfreq; 
        end
        
        localhandles(12).String(1:end-3)=num2str(newAC,'%07.3f');
        SRSfreq(source,eventdata,newAC)
        
        fbtime=toc(fbtic);
        setappdata(main,'PID_timestamp',currenttime);
        setappdata(main,'PID_oldvalue',ycentroid);
        setappdata(main,'PID_Iterm',Iterm);
    end

    function setidealY(source,eventdata)
        setappdata(main,'IdealY',str2num(get(source,'string')))
    end

%% functions that actually do stuff for fringe camera
    function fringe_fullscreen(source,eventdata)
        temp=getappdata(main);
        preview(temp.fringe_video_handle)
        %beep
        set(source,'value',0)
    end

    function fringe_camera_arm(source,eventdata)
        %state of button: 1=on, 0=off
        temp=getappdata(main);
        [localhandles]=get_figure_handles(source,eventdata,fringe_window_handle);
        if(get(source,'value'))
            %turn camera flag on
            setappdata(main,'camera2Flag',1)
            localhandles(1).Enable='off';
            set(localhandles(9),'string','Camera Armed');
            set(localhandles(9),'backgroundcolor',[0.5 1 0.5]);
            %make gain and shutter control invisible
            set(localhandles(4),'visible','off')
            set(localhandles(6),'visible','off')
            set(localhandles(8),'visible','off')
            set(localhandles(3).Children(1).Children(1),'xticklabel',[]);
            set(localhandles(3).Children(1).Children(1),'xtick',[]);
            set(localhandles(3).Children(1).Children(1),'yticklabel',[]);
            set(localhandles(3).Children(1).Children(1),'ytick',[]);
            %set the axes to not reset plot propertes
            set(localhandles(3).Children(1).Children(1),'nextplot','add');
            set(localhandles(3).Children(1).Children(1),'ydir','reverse');
            set(localhandles(3).Children(1).Children(1),'xlim',[0 640],'ylim',[0 480])
        else
            %turn camera off
            setappdata(main,'camera2Flag',0)
            set(localhandles(9),'string','Camera Ready');
            set(localhandles(9),'backgroundcolor',[1 0.5 0.5]);
            %make gain and shutter controls visible
            localhandles(1).Enable='on';
            set(localhandles(4),'visible','on')
            set(localhandles(6),'visible','on')
            set(localhandles(8),'visible','on')
        end
    end

    function change_fringe_gain(source,eventdata)
        %get temporary data and pointers
        temp=getappdata(main);
        [localhandles]=get_figure_handles(source,eventdata,fringe_window_handle);
        newgain=get(localhandles(8),'value');%get the new gain value
        %write value to camera
        temp.fringe_source_data.Gain=newgain;
        %write value to indicator
        set(localhandles(7),'string',[num2str(newgain,'%10.1f') ' dB'])
        %write source data back to application data
        setappdata(main,'fringe_source_data',temp.fringe_source_data);
        %update image
        wait_a_second(source,eventdata,fringe_window_handle);
        frame=getsnapshot(temp.fringe_video_handle);
        frame_small=imresize(frame,[480 640]);
        good_to_go(source,eventdata,fringe_window_handle);
        imshow(frame_small,'parent',localhandles(3).Children(1).Children(1));
    end

    function change_fringe_shutter(source,eventdata)
        %get temporary data and pointers
        temp=getappdata(main);
        [localhandles]=get_figure_handles(source,eventdata,fringe_window_handle);
        newshutter=get(localhandles(6),'value');%get the new gain value
        %write value to camera
        temp.fringe_source_data.Shutter=newshutter;
        %write value to indicator
        set(localhandles(5),'string',[num2str(newshutter,'%10.3f') ' ms'])
        %write source data back to application data
        setappdata(main,'fringe_source_data',temp.fringe_source_data);
        %update image
        wait_a_second(source,eventdata,fringe_window_handle);
        frame=getsnapshot(temp.fringe_video_handle);
        frame_small=imresize(frame,[480 640]);
        good_to_go(source,eventdata,fringe_window_handle);
        imshow(frame_small,'parent',localhandles(3).Children(1).Children(1));
    end

    function [imdata_compressed]=fringe_annotation(source,eventdata,imdata)
        imdata_compressed=mean(imdata,2);
        %compress data
        imdata_compressed=uint8(imdata_compressed./max(imdata_compressed)*200);
        %set(f,'CurrentAxes',ax2);
        %rectangle('parent',ax2,'position',[600 0 100 500],'facecolor','k')
        [localhandles]=get_figure_handles(source,eventdata,fringe_window_handle);
        plot(localhandles(3).Children(1).Children(1),640-uint16(imdata_compressed(1:end)),1:(480),'r','linewidth',2);
        %[~,peaklocs]=findpeaks(imdata_compressed);
        %         Y=fft(imdata_compressed);
        %         N=50;
        %         fringe_fft=[now Y(1:1+N)'];
    end

%% functions that actually do stuff for arduino
    function arduino_mode(source,eventdata)
        temp=getappdata(main);
        %update app data with new UPSI to display
        setappdata(main,'UPSInumber',str2num(get(eventdata.NewValue,'String')));
    end

    function arduinocomms(source,eventdata)
        [localhandles]=get_figure_handles(source,eventdata,arduino_window_handle);
        if(get(source,'value'))
            %open the port and lock the selector
            %get identity of port
            portstrings=get(localhandles(3),'string');
            portID=portstrings{get(localhandles(3),'value')};
            
            % Find a serial port object.
            obj2 = instrfind('Type', 'serial', 'Port', portID, 'Tag', '');
            
            % Create the serial port object if it does not exist
            % otherwise use the object that was found.
            if isempty(obj2)
                obj2 = serial(portID);
            else
                fclose(obj2);
                obj2 = obj2(1);
            end
            set(obj2,'Timeout',1); %do a 1 second timeout
            
            %open the serial object
            fopen(obj2);
            pause(0.25)
            set(localhandles(3),'enable','off');
            set(localhandles(2),'string','Port Open');
            set(localhandles(5),'enable','on');
            set(localhandles(6),'enable','on');
            setappdata(main,'arduino_comm',obj2);
            temp=getappdata(main);
            if(~isfield(temp,'UPSIdata'))
                pause(1)
                data2 = query(obj2, 'r');
                spaces=strfind(data2,' ');
                H1=str2num(data2(1:spaces(1)-1));
                T1=str2num(data2(spaces(1)+1:spaces(2)-1));
                H2=str2num(data2(spaces(2)+1:spaces(3)-1));
                T2=str2num(data2(spaces(3)+1:spaces(4)-1));
                temp.UPSIdata(1,:)=[now H1 T1 H2 T2];
                setappdata(main,'UPSIdata',temp.UPSIdata)
            end
        else
            %close the port and unlock the selector
            %check app data
            temp=getappdata(main);
            if(isfield(temp,'arduino_comm'))
                fclose(temp.arduino_comm);
                rmappdata(main,'arduino_comm');
            end
            set(localhandles(3),'enable','on');
            set(localhandles(2),'string','Port Closed');
            set(localhandles(5),'enable','off');
            set(localhandles(6),'enable','off');
        end
        
    end

    function update_arduino_display(source,eventdata)
        %update display
        [localhandles]=get_figure_handles(source,eventdata,arduino_window_handle);
        %cla(ax20); cla(ax21)
        temp=getappdata(main);
        if(~isfield(temp,'UPSIdata')||size(temp.UPSIdata,1)==1)
            %do not attempt to plot if there is only one data point
            return
        end
        plot(localhandles(end),temp.UPSIdata(:,1),temp.UPSIdata(:,1+(temp.UPSInumber-1)*2+1),'.');
        NumTicks = 6;
        L =[temp.UPSIdata(1,1) temp.UPSIdata(end,1)];
        set(localhandles(end),'XTick',linspace(L(1),L(2),NumTicks))
        if(diff(str2num(datestr(L,'DD')))>0) %if data spans more than one day
            datetick(localhandles(end),'x','(DD).HH','keepticks')
        else %only one day, show minutes
            datetick(localhandles(end),'x','HH:MM','keepticks')
        end
        plot(localhandles(end-1),temp.UPSIdata(:,1),temp.UPSIdata(:,1+(temp.UPSInumber-1)*2+2),'.');
    end

    function update_arduino(source,eventdata,savelogic);
        temp=getappdata(main);
        if(temp.arduino_comm.BytesAvailable~=0)
            flushinput(temp.arduino_comm);
        end
        data2 = query(temp.arduino_comm, 'r');
        spaces=strfind(data2,' ');
        H1=str2num(data2(1:spaces(1)-1));
        T1=str2num(data2(spaces(1)+1:spaces(2)-1));
        H2=str2num(data2(spaces(2)+1:spaces(3)-1));
        T2=str2num(data2(spaces(3)+1:spaces(4)-1));
        temp.UPSIdata(end+1,:)=[now H1 T1 H2 T2];
        setappdata(main,'UPSIdata',temp.UPSIdata);
        update_arduino_display(source,eventdata);
    end

    function inject(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,arduino_window_handle);
        temp=getappdata(main);
        data2=query(temp.arduino_comm,'s');
        set(localhandles(4),'string',[datestr(now) ' ' data2])
    end

    function burst(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,arduino_window_handle);
        temp=getappdata(main);
        data2=query(temp.arduino_comm,'1');
        for i=1:19
            data2=fgets(temp.arduino_comm);
        end
        set(localhandles(4),'string',[datestr(now) ' Burst'])
        
    end
%% functions that actually do stuff for the SRS function generator
    function SRScommsDC(source,eventdata)
        if(get(source,'value'))
            stop(fasttimer)
            %get identity of port
            localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
            portstrings=get(localhandles(end-14),'string');
            portID=portstrings{get(localhandles(end-14),'value')};
            DS345_DC=DS345Device(portID);
            setappdata(main,'DS345_DC',DS345_DC);
            set(localhandles(end-14),'enable','off');
            set(source,'string','Port Open');
            stat=DS345_DC.offset;
            stat=num2str(str2num(stat),'%+07.4f');
            set(localhandles(end-20),'string',[stat ' V '])
            %turn on all the buttons
            for i=21:26
                set(localhandles(end-i),'enable','on')
            end
            start(fasttimer)
        else
            %close the port
            temp=getappdata(main);
            temp.DS345_DC.delete;
            %clean up application data
            rmappdata(main,'DS345_DC');
            localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
            set(localhandles(end-14),'enable','on');
            set(source,'string','Port Closed');
            for i=21:26
                set(localhandles(end-i),'enable','off')
            end
        end
    end

    function SRScommsAC(source,eventdata)
        if(get(source,'value'))
            stop(fasttimer)
            %get identity of port
            localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
            portstrings=get(localhandles(end-17),'string');
            portID=portstrings{get(localhandles(end-17),'value')};
            DS345_AC=DS345Device(portID);
            setappdata(main,'DS345_AC',DS345_AC);
            set(localhandles(end-17),'enable','off');
            set(source,'string','Port Open');
            stat=DS345_AC.amplitude;
            set(localhandles(end-36),'string',[stat(1:end-2) ' VP'])
            stat=DS345_AC.frequency;
            stat=num2str(str2num(stat),'%07.3f');
            set(localhandles(end-28),'string',[stat ' Hz'])
            %turn on all the buttons
            for i=29:34
                set(localhandles(end-i),'enable','on')
            end
            for i=37:38
                set(localhandles(end-i),'enable','on')
            end
            start(fasttimer)
        else
            %close the port
            temp=getappdata(main);
            temp.DS345_AC.delete;
            %clean up application data
            rmappdata(main,'DS345_AC');
            localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
            set(localhandles(end-17),'enable','on');
            set(source,'string','Port Closed');
            for i=29:34
                set(localhandles(end-i),'enable','off')
            end
            for i=37:38
                set(localhandles(end-i),'enable','off')
            end
        end
    end

    function SRSDC_mode(source,eventdata)
        temp=getappdata(main);
        temp.DS345_DC.set_func(lower(get(eventdata.NewValue,'String')))
    end

%     function SRSamp(source,eventdata)
%         ID=get(source,'tag');
%         temp=getappdata(main);
%         temp.DS345_DC.set_amp(num2str(get(source,'value')),'VP')
%         localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
%         sublocalhandles=localhandles.Children;
%         set(sublocalhandles(,'string',['Set: ' num2str(get(source,'value')) 'VP'])
%     end

    function newSRS(source,eventdata,label)
        temp=getappdata(main);
        localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
        %        source=source.Source; %headdesk
        %a button was pushed
        %figure out what is being done
        SRSwhichone=source.Tag(1:2);
        SRSvalue=source.Tag(4:7);
        %DC OFFSET localhandles(end-20)
        %AC FREQ localhandles(end-28)
        %AC AMP localhandles(end-36)
        if(strcmp(SRSvalue,'OFFS'))
            SRSnumeric=str2num(localhandles(end-20).String(1:end-3));
            SRSunit=localhandles(end-20).String(end-2:end);
            SRSincrement=str2num(source.Tag(9:end));
            SRSincrement=SRSincrement./1000;
            newsetpoint=num2str(SRSnumeric+SRSincrement,'%+07.4f');
            localhandles(end-20).String(1:end-3)=newsetpoint;
            eval(['temp.DS345_' SRSwhichone '.set_' strtrim(lower(SRSvalue)) '(''' newsetpoint ''')'])
        elseif(strcmp(SRSvalue,'AMP '))
            SRSnumeric=str2num(localhandles(end-36).String(1:end-3));
            SRSunit=localhandles(end-36).String(end-2:end);
            SRSincrement=str2num(source.Tag(9:end));
            newsetpoint=num2str(SRSnumeric+SRSincrement);
            localhandles(end-36).String=[num2str(SRSnumeric+SRSincrement,'%.2f') ' VP'];
            eval(['temp.DS345_' SRSwhichone '.set_' strtrim(lower(SRSvalue)) '(''' newsetpoint ''',''VP'')'])
        elseif(strcmp(SRSvalue,'FREQ'))
            SRSnumeric=str2num(localhandles(end-28).String(1:end-3));
            SRSunit=localhandles(end-28).String(end-2:end);
            SRSincrement=str2num(source.Tag(9:end));
            newsetpoint=num2str(SRSnumeric+SRSincrement);
            localhandles(end-28).String(1:end-3)=num2str(SRSnumeric+SRSincrement,'%07.3f');
            eval(['temp.DS345_' SRSwhichone '.set_' strtrim(lower(SRSvalue)) '(''' newsetpoint ''')'])
        end
        
        
        
        
        
    end

    function SRSoffs(source,eventdata,setY)
        temp=getappdata(main);
        %localhandles=get_figure_handles(source,eventdata,microscope_window_handle);
        temp.DS345_DC.set_offs(num2str(setY))
    end
%
    function SRSfreq(source,eventdata,newAC)
        temp=getappdata(main);
        temp.DS345_AC.set_freq(num2str(newAC,'%.3f'));
        %set(SRSfreq_lab,'string',['Set: ' num2str(get(source,'value'),'%.2f') 'Hz'])
    end


%% functions that actually do stuff for the MKS and Lauda board

    function Laudacomms(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        if(get(source,'value'))
            stop(fasttimer)
            %get identity of port
            
            portstrings=get(localhandles(18),'string');
            portID=portstrings{get(localhandles(18),'value')};
            
            set(localhandles(18),'enable','off');
            set(localhandles(17),'string','Port Open');
            
            %set(localhandles(),'enable','on')
            
            
            % Find a serial port object.
            obj1 = instrfind('Type', 'serial', 'Port', portID, 'Tag', '');
            
            % Create the serial port object if it does not exist
            % otherwise use the object that was found.
            if isempty(obj1)
                obj1 = serial(portID);
            else
                fclose(obj1);
                obj1 = obj1(1);
            end
            
            set(obj1, 'Terminator', {'CR/LF','CR/LF'});
            
            % Connect to instrument object, obj1.
            fopen(obj1);
            setappdata(main,'LaudaRS232',obj1)
            
            update_Lauda(source,eventdata,0)
            
            
            
        else
            %close the port
            temp=getappdata(main);
            set(localhandles(18),'enable','on');
            set(localhandles(17),'string','Port Closed');
            set(localhandles(3),'enable','off');
            set(localhandles(26),'enable','off');
            set(localhandles(27),'enable','off');
            set(localhandles(2),'enable','off');
            fclose(temp.LaudaRS232);
            rmappdata(main,'LaudaRS232');
            
        end
    end

    function update_Lauda(source,eventdata,savelogic)
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        temp=getappdata(main);
        obj1=temp.LaudaRS232;
        data8 = query(obj1, 'STATUS');
        if(str2num(data8)~=0)
            error('Lauda communication failure')
        end
        
        %read status of power
        onoff = query(obj1, 'IN_MODE_02');
        %1 means off, 0 means on
        if(str2num(onoff)==1)
            %pump is off
            
            set(localhandles(3),'string','Pump off','Value',0,'enable','on')
        else
            %pump is on
            set(localhandles(3),'string','Pump on','value',1,'enable','on')
        end
        
        cooleronoff=query(obj1,'IN_SP_02');
        if(str2num(cooleronoff)==2)
            %automatic
            set(localhandles(26),'string','Chiller Auto','Value',1,'enable','on');
        elseif(str2num(cooleronoff)==0)
            %off
            set(localhandles(26),'string','Chiller Off','Value',0,'enable','on');
        else
            error('unrecognized cooler mode!')
        end
        
        controler_internalvsexternal=query(obj1,'IN_MODE_01');
        if(str2num(controler_internalvsexternal)==1)
            %automatic
            set(localhandles(27),'string','Control via PT100','Value',1,'enable','on');
        elseif(str2num(controler_internalvsexternal)==0)
            %off
            set(localhandles(27),'string','Control via Bath','Value',0,'enable','on');
        else
            error('unrecognized control mode!')
        end
        
        
        %read current T setpoint
        setT=query(obj1, 'IN_SP_00');
        
        setT=strtrim(setT);
        
        if(setT(1)=='0')
            setT(1)=[];
        end
        
        set(localhandles(2),'string',setT,'enable','on')
        
        actualT=query(obj1, 'IN_PV_00');
        
        actualT=strtrim(actualT);
        
        if(actualT(1)=='0')
           actualT(1)=[]; 
        end
        
        externalT=query(obj1, 'IN_PV_03');
        
        externalT=strtrim(externalT);
        
        if(externalT(1)=='0')
           externalT(1)=[]; 
        end
        
        set(localhandles(1),'string',['Int:' actualT ' Ext: ' externalT],'enable','on')
        
        localhandles(9).Data(1,2)=str2num(setT);
        
        temp.Laudadatalog(end+1,:)=[now str2num(onoff) str2num(setT) str2num(actualT) str2num(externalT)];
        if(savelogic)
            setappdata(main,'Laudadatalog',temp.Laudadatalog);
        end
    end

    function LaudaPower(source,eventdata)
        temp=getappdata(main);
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        obj1=temp.LaudaRS232;
        if(get(source,'value'))
            qd=query(obj1,'START');
            set(localhandles(3),'string','Pump on')
        else
            qd=query(obj1,'STOP');
            set(localhandles(3),'string','Pump off')
        end
    end

    function LaudaChiller(source,eventdata)
        temp=getappdata(main);
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        obj1=temp.LaudaRS232;
        if(get(source,'value'))
            qd=query(obj1,'OUT_SP_02_02');
            set(localhandles(26),'string','Chiller auto')
        else
            qd=query(obj1,'OUT_SP_02_00');
            set(localhandles(26),'string','Chiller off')
        end
    end

    function LaudaControl(source,eventdata)
        temp=getappdata(main);
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        obj1=temp.LaudaRS232;
        if(get(source,'value'))
            qd=query(obj1,'OUT_MODE_01_1');
            set(localhandles(27),'string','Control via PT100')
        else
            qd=query(obj1,'OUT_MODE_01_0');
            set(localhandles(27),'string','Control via Bath')
        end
    end

    function Lauda_send_T(source,eventdata,varargin)
        if(length(varargin)==0)
            setT=str2num(get(source,'string'));
        else
            setT=varargin{1};
        end
        %to do: add saftey feature to prevent user from typing in something
        %dumb
        temp=getappdata(main);
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        obj1=temp.LaudaRS232;
        qd=query(obj1,['OUT_SP_00_' num2str(setT,'%5.2f')]);
    end

    function Julabocomms(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        if(get(source,'value'))
            stop(fasttimer)
            %get identity of port
            
            portstrings=get(localhandles(25),'string');
            portID=portstrings{get(localhandles(25),'value')};
            
            set(localhandles(25),'enable','off');
            set(localhandles(24),'string','Port Open');
            
            
            % Find a serial port object.
            obj1 = instrfind('Type', 'serial', 'Port', portID, 'Tag', '');
            
            % Create the serial port object if it does not exist
            % otherwise use the object that was found.
            if isempty(obj1)
                obj1 = serial(portID);
            else
                fclose(obj1);
                obj1 = obj1(1);
            end
            
            % Configure instrument object, obj1.
            set(obj1, 'Timeout', 1.0);
            
            % Configure instrument object, obj1.
            set(obj1, 'Terminator', {'CR/LF','CR'});
            
            obj1.DataBits=7;
            obj1.FlowControl='hardware';
            obj1.Parity='even';
            obj1.BaudRate=4800;
            
            % Connect to instrument object, obj1.
            fopen(obj1);
            setappdata(main,'JulaboRS232',obj1)
            
            update_Julabo(source,eventdata,0)
        else
            %close the port
            temp=getappdata(main);
            set(localhandles(25),'enable','on');
            set(localhandles(24),'string','Port Closed');
            set(localhandles(22),'string','?','enable','off');
            set(localhandles(21),'string','?','enable','off');
            set(localhandles(23),'string','Pump ?','Value',0,'enable','off');
            fclose(temp.JulaboRS232);
            rmappdata(main,'JulaboRS232');
        end
    end

    function update_Julabo(source,eventdata,savelogic)
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        temp=getappdata(main);
        obj1=temp.JulaboRS232;
        data8 = query(obj1, 'status');
        if(strcmp(strtrim(data8),'03 REMOTE START')|strcmp(strtrim(data8),'02 REMOTE STOP'))
            %it's all good
        else
            error('Julabo communication failure')
        end
        
        %read status of power
        onoff = query(obj1, 'in_mode_05');
        %1 means off, 0 means on
        if(str2num(onoff)==0)
            %pump is off
            
            set(localhandles(23),'string','Pump off','Value',0,'enable','on')
        else
            %pump is on
            set(localhandles(23),'string','Pump on','value',1,'enable','on')
        end
        
        %read current T setpoint
        setT=query(obj1, 'in_sp_00');
        
        set(localhandles(22),'string',setT(1:end-2),'enable','on')
        
        localhandles(9).Data(1,5)=str2num(setT(1:end-2));
        
        actualT=query(obj1, 'in_pv_00');
        
        set(localhandles(21),'string',actualT(1:end-2),'enable','on')
        
        
        
        temp.Julabodatalog(end+1,:)=[now str2num(onoff) str2num(setT) str2num(actualT)];
        if(savelogic)
            setappdata(main,'Julabodatalog',temp.Julabodatalog);
        end
    end

    function JulaboPower(source,eventdata)
        temp=getappdata(main);
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        obj1=temp.JulaboRS232;
        if(get(source,'value'))
            fprintf(obj1,'out_mode_05 1'); %start the pump
            set(localhandles(23),'string','Pump on')
        else
            fprintf(obj1,'out_mode_05 0'); %stop the pump
            set(localhandles(23),'string','Pump off')
        end
    end

    function Julabo_send_T(source,eventdata,varargin)
        if(length(varargin)==0)
            setT=str2num(get(source,'string'));
        else
            setT=varargin{1};
        end
        %to do: add saftey feature to prevent user from typing in something
        %dumb
        temp=getappdata(main);
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        obj1=temp.JulaboRS232;
        fprintf(obj1,['out_sp_00 ' num2str(setT,'%5.2f')]);
    end


    function MKScomms(source,eventdata)
        if(get(source,'value'))
            %open the port and lock the selector
            %get identity of port
            localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
            portstrings=get(localhandles(20),'string');
            portID=portstrings{get(localhandles(20),'value')};
            
            % Find a serial port object.
            obj1 = instrfind('Type', 'serial', 'Port', portID, 'Tag', '');
            
            % Create the serial port object if it does not exist
            % otherwise use the object that was found.
            if isempty(obj1)
                obj1 = serial(portID);
            else
                fclose(obj1);
                obj1 = obj1(1);
            end
            
            set(obj1, 'Terminator', {70,''});
            set(obj1,'Timeout',1); %do a 1 second timeout
            %open the serial object
            fopen(obj1);
            setappdata(main,'MKS946_comm',obj1)
            set(localhandles(20),'enable','off');
            set(localhandles(19),'string','Port Open');
            set(localhandles(13),'enable','on');
            
            localhandles(10).Children(2).Enable='on';
            localhandles(11).Children(2).Enable='on';
            %set(mks3_r1,'enable','on');
            %set(mks3_r2,'enable','on');
            %set(mks3_r3,'enable','on');
            %set(mks4_r1,'enable','on');
            %set(mks4_r2,'enable','on');
            %set(mks4_r3,'enable','on');
            update_MKS_values(source,eventdata,0)
            
        else
            %close the port and unlock the selector
            %check app data
            temp=getappdata(main);
            if(isfield(temp,'MKS946_comm'))
                fclose(temp.MKS946_comm);
                rmappdata(main,'MKS946_comm');
            end
            localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
            set(localhandles(20),'enable','on');
            set(localhandles(19),'string','Port Closed');
            set(localhandles(13),'enable','off');
            localhandles(10).Children(2).Enable='off';
            localhandles(11).Children(2).Enable='off';
            %             set(mks3_r1,'enable','off');
            %             set(mks3_r2,'enable','off');
            %             set(mks3_r3,'enable','off');
            %             set(mks4_r1,'enable','off');
            %             set(mks4_r2,'enable','off');
            %             set(mks4_r3,'enable','off');
            %             set(mks3sp,'enable','off');
            %             set(mks4sp,'enable','off');
        end
        
    end

    function update_MKS_values(source,eventdata,savelogic)
        %query the state of ch3 and 4
        %hard code for now
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        stat=MKSsend(source,eventdata,'QMD3?');
        switch stat %switch on response only
            case 'OPEN',
                localhandles(11).Children(5).Value=1;
                MKS3onoff=NaN;
            case 'CLOSE',
                localhandles(11).Children(4).Value=1;
                MKS3onoff=0;
            case 'SETPOINT'
                localhandles(11).Children(3).Value=1;
                MKS3onoff=1;
        end
        
        stat=MKSsend(source,eventdata,'QMD4?');
        switch stat
            case 'OPEN',
                localhandles(10).Children(5).Value=1;
                MKS4onoff=NaN;
            case 'CLOSE',
                localhandles(10).Children(4).Value=1;
                MKS4onoff=0;
            case 'SETPOINT'
                localhandles(10).Children(3).Value=1;
                MKS4onoff=1;
        end
        
        %manually query setpoints
        stat=MKSsend(source,eventdata,'QSP4?');
        F_humid=str2num(stat)*MKS4onoff;
        %clean up formatting
        stat=sprintf('%.2f',str2num(stat));
        
        set(localhandles(10).Children(2),'string',stat(1:4)); %keep only three sig figs
        
        %manually query setpoints
        stat=MKSsend(source,eventdata,'QSP3?');
        F_dry=str2num(stat)*MKS3onoff;
        stat=sprintf('%.2f',str2num(stat));
        set(localhandles(11).Children(2),'string',stat(1:4));
        
        %and fill in values of table
        localhandles(9).Data(1,4)=F_dry+F_humid;
        
        %then fill in actual values
        stat=MKSsend(source,eventdata,'FR3?');
        stat=sprintf('%.2f',str2num(stat));
        localhandles(11).Children(1).String=[stat ' sccm'];
        
        stat=MKSsend(source,eventdata,'FR4?');
        stat=sprintf('%.2f',str2num(stat));
        localhandles(10).Children(1).String=[stat ' sccm'];
        
        %and fill in RH if T is known
        if(localhandles(9).Data(1,2)~=-999)
            %currently assuming RT = 20 degC!
            if(isa(str2num(localhandles(22).String),'numeric'))
                Bath_T=str2num(localhandles(22).String);
            else
                Bath_T=19;
            end
            Bath_saturation=water_vapor_pressure(source,eventdata,Bath_T+273.15);
            Trap_saturation=water_vapor_pressure(source,eventdata,localhandles(9).Data(1,2)+273.15);
            RH=round(100*F_humid/(F_humid+F_dry)*Bath_saturation/Trap_saturation,1);
            if(~isempty(RH))
                localhandles(9).Data(1,3)=RH;
            end
        end
        
        temp=getappdata(main);
        temp.MKSdatalog(end+1,:)=[now F_dry F_humid];
        if(savelogic)
            setappdata(main,'MKSdatalog',temp.MKSdatalog);
        end
    end

    function [response] = MKSsend(source,eventdata,varargin)
        temp=getappdata(main);
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        if(length(varargin)==1)
            arg1=varargin{1};
        else
            arg1=localhandles(14).String;
        end
        querytext=['@253' arg1 ';FF'];
        data1 = query(temp.MKS946_comm, querytext);
        if(data1=='F')
            warning([datestr(now) ' MKS946 out of sequence. Performing additional read'])
            data1 = fscanf(temp.MKS946_comm);
        end
        if(isempty(data1))
            error('No data returned by MKS RS232')
        end
        data2 = fscanf(temp.MKS946_comm);
        %check for errors
        if(strcmp(data1(5:7),'NAK'))
            error('Communication error to MKS!')
        end
        response=data1(8:end-2); %trim pre- and post-statements
        %if no arguement was specified, it was entered manually and is
        %returned to the display
        %if(length(varargin)==0)
        set(localhandles(12),'string',data1)
        %end
    end

    function MKS_mode(source,eventdata)
        %figure out where the button push happened
        pan_num=get(source,'tag');
        selection=[];
        if(strcmp(upper(get(eventdata.NewValue,'String')),'OPEN'))
            selection = questdlg('Really OPEN valve?','Run OPEM valve?',...
                'Yes','No','No');
        end
        
        if(~isempty(selection))
            switch selection
                case 'Yes',
                    %let it  run
                case 'No'
                    source.Children(3).Value=0;
                    source.Children(4).Value=0;
                    source.Children(5).Value=0;
                    return
            end
        end
        %       set(MKScommandline,'string',['QMD' pan_num '!' upper(get(eventdata.NewValue,'String'))])
        MKSsend(source,eventdata,['QMD' pan_num '!' upper(get(eventdata.NewValue,'String'))]);
    end


    function MKSchangeflow(source,eventdata,channel,value)
        %figure out where the button push happened
        if(isnan(value))
            value=get(source,'string'); %get user-entered data
            %set formatting to d.ddE+ee
            formatted_value=sprintf('%.2E',str2num(value));
        else
            formatted_value=sprintf('%.2E',value);
        end
        MKSsend(source,eventdata,['QSP' num2str(channel) '!' formatted_value]);
    end

    function p_circ=water_vapor_pressure(source,eventdata,T)
        
        %http://www.watervaporpressure.com/
        %input T in celcius!
        %output in torr
        %A=8.07131;
        %B=1730.64;
        %C=233.426;
        %RANGE: 1-100 degC
        
        %http://webbook.nist.gov/cgi/cbook.cgi?ID=C7732185&Mask=4&Type=ANTOINE&Plot=on#ref-4
        %Stull, 1947
        %T in Kelvin
        %P in bar
        A=4.6543;
        B=1435.264;
        C=-64.848;
        
        p_circ=10.^(A-(B./(C+T)));
        
    end

    function cleartable_fcn(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        localhandles(9).Data=[0 -999 -999 -999];
    end

    function edit_table(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        data=localhandles(9).Data;
        localhandles(9).Data=data;
    end

    function addrow_fcn(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        data=localhandles(9).Data;
        data(end+1,:)=data(end,:); %if data is an array.
        data(end,1)=data(end,1)+0.5; %make default 30 minutes per step
        localhandles(9).Data=data;
    end

    function temp_fig=sim_ramp_fcn(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        data=localhandles(9).Data;
        fc1=200;
        fc2=200;
        %put in 10 points in between every one that the user requests
        for i=0:size(data,1)-2
            newdata(i*10+1:i*10+10,:)=[linspace(data(i+1,1),data(i+2,1),10)' ...
                linspace(data(i+1,2),data(i+2,2),10)' ...
                linspace(data(i+1,3),data(i+2,3),10)' ...
                linspace(data(i+1,4),data(i+2,4),10)' ...
                linspace(data(i+1,5),data(i+2,5),10)'];
        end
        %repoint the data towards new data
        data=newdata;
        flow_total=data(:,4);
%       %  ASSUME 20 degC ROOM! Obviously this is wrong!
%         if(isa(str2num(localhandles(22).String),'numeric'))
%             Bath_T=str2num(localhandles(22).String);
%         else
%             Bath_T=19;
%         end
        Bath_T=data(:,5);
        p_source=water_vapor_pressure(source,eventdata,Bath_T+273.15); %in bar
        p_trap_sat=water_vapor_pressure(source,eventdata,data(:,2)+273.15); %in bar
        p_trap=p_trap_sat.*data(:,3)/100; %in bar
        maxRH=p_source./p_trap_sat;
        flows=[1-p_trap./p_source p_trap./p_source]; %unscaled flows
        over_range=flows>1;
        flows(over_range==1)=1;
        under_range=flows<0;
        flows(under_range==1)=0;
        flows=flows.*repmat(flow_total,size(flows)./size(flow_total));
        T_setpoints=data(:,2);
        Julabo_setpoints=data(:,5);
        dwpt_thy=water_dew_pt(flows(:,2)./sum(flows,2).*p_source)-273.15;
        temp_fig=figure('position',[100 100 600 700]);
        subplot(3,1,[1 2])
        [temp_ax,h1,h2]=plotyy(data(:,1),T_setpoints,data(:,1),p_trap./p_trap_sat*100);
        l2=line(temp_ax(1),data(:,1),Julabo_setpoints);
        l3=line(temp_ax(1),data(:,1),dwpt_thy);
        l1=line(temp_ax(2),newdata(:,1),maxRH*100);
        set(l1,'linestyle',':','color','r');
        set(l3,'linestyle','-.','color','k')
        set(h2,'linestyle','--','color','r')
        set(l2,'linestyle','-','color',[0 0.5 0])
        
        xlabel('Time (hrs)')
        ylabel(temp_ax(1),'Temperature (�C)')
        legend(temp_ax(1),'Trap','Hookah','Dewpt','location','northwest')
         legend(temp_ax(2),'Trap RH','Max RH','location','northeast')
        ylabel(temp_ax(2),'RH in trap (%)')
        temp_ax(1).YLim=[min([data(:,2); Julabo_setpoints])-1 max([data(:,2); Julabo_setpoints])+1];
        temp_ax(1).YTickMode='Auto';
        temp_ax(2).YLim=[min([p_trap./p_trap_sat*100; maxRH*100])-5 max([[p_trap./p_trap_sat*100; maxRH*100]])+5];
        temp_ax(2).YTickMode='Auto';
        subplot(3,1,3)
        plot(data(:,1),flows(:,1),data(:,1),flows(:,2))
        xlabel('Time (hrs)')
        ylabel('Flow (sccm)')
        legend('Dry','Humid')
        
        if(any(dwpt_thy>33))
            warndlg('Dewpoint exceeds 33�C. Be careful!')
        end
        
        setappdata(main,'Ramp_data',unique([data(:,1) flows T_setpoints Julabo_setpoints],'rows'))
        %TO FIX: currently assumes everything is linear, but RH depends
        %nonlinearly on temperature...
    end



    function drive_ramps_fcn(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,MKS_window_handle);
        if(source.Value)
            stop(fasttimer)
            stop(errorcatchtimer)
            temp_fig=sim_ramp_fcn(source,eventdata);
            selection = questdlg('Run this ramp?','Run this ramp?',...
                'Yes','No','No');
            if(strcmp(selection,'Yes'))
                dt_str=inputdlg('Start ramp at what relative time?','Ramp time start',1,{'0'});
                dt_num=str2num(dt_str{1});
                set(localhandles(9),'enable','off')
                setappdata(main,'RampFlag',1)
                set(localhandles(5),'string','Ramping...')
                setappdata(main,'RampTime_init',now-dt_num/24);
                %setappdata(m,'RampData',get(hum_table,'data'));
                close(temp_fig)
            else
                %turn button back off
                localhandles(5).Value=0;
            end
            start(fasttimer)
            start(errorcatchtimer)
        else
            set(localhandles(9),'enable','on')
            setappdata(main,'RampFlag',0)
            set(localhandles(5),'string','Ramp Trap')
        end
    end



%% functions that actually do stuff for andor
    function andor_initalize(source,eventdata)
        %initalize camera
        %check to see if the camera is already connected
        wait_a_second(source,eventdata,Andor_window_handle)
        [ret,status]=AndorGetStatus();
        if(status==atmcd.DRV_IDLE)
            %camera already connected, no need to reinitialize the
            %connection
        else
            ret=AndorInitialize('');
        end
        good_to_go(source,eventdata,Andor_window_handle)
        CheckError(ret);
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        update_andor_output(source,eventdata,'Connected to Andor')
        %check and synchronize status of chiller
        [ret,Cstat]=IsCoolerOn;
        setappdata(main,'AndorFlag',1)
        if(Cstat)
            %chiller is already on
            set(localhandles(16),'value',1,'string','Cooler ON')
            
            %check and initalize temperature of chiller if it is on
            [ret, SensorTemp, TargetTemp, AmbientTemp, CoolerVolts]=GetTemperatureStatus();
            localhandles(13).String=[num2str(SensorTemp) '�C'];
            localhandles(14).String=[num2str(TargetTemp) '�C'];
        else
            %chiller is off
            %do nothing
        end
        
        localhandles(10).Enable='on';
        
        if(localhandles(11).Value==1)
            %single scan mode
            localhandles(5).Enable='off';
            localhandles(7).Enable='off';
            [ret]=SetAcquisitionMode(1);                  %   Set acquisition mode; 1 for single scan
            CheckWarning(ret);
            update_andor_output(source,eventdata,'Set up Single Scan')
            [ret]=SetExposureTime(str2num(localhandles(9).String));                  %   Set exposure time in second
            CheckWarning(ret);
            update_andor_output(source,eventdata,['Exposure Time: ' localhandles(9).String ' s'])
        elseif(localhandles(11).Value==2)
            %kinetic series mode
            localhandles(5).Enable='on';
            localhandles(7).Enable='on';
            [ret]=SetAcquisitionMode(3);                  %   Set acquisition mode; 3 for Kinetic Series
            CheckWarning(ret);
            update_andor_output(source,eventdata,'Set up Kinetic Series')
            
            [ret]=SetNumberKinetics(str2num(localhandles(7).String));
            CheckWarning(ret);
            update_andor_output(source,eventdata,['Length of Kinetic Series: ' localhandles(7).String])
            
            [ret]=SetExposureTime(str2num(localhandles(9).String));                  %   Set exposure time in second
            CheckWarning(ret);
            update_andor_output(source,eventdata,['Exposure Time: ' localhandles(9).String ' s'])
            
            [ret]=SetKineticCycleTime(str2num(localhandles(5).String));           %set kinetic cycle time
            CheckWarning(ret);
            update_andor_output(source,eventdata,['Cycle Time: ' localhandles(5).String ' s'])
        end
        
        [ret]=SetReadMode(0);                         %   Set read mode; 0 for FVP
        CheckWarning(ret);
        [ret]=SetTriggerMode(0);                      %   Set internal trigger mode
        CheckWarning(ret);
        [ret,XPixels, YPixels]=GetDetector;           %   Get the CCD size
        CheckWarning(ret);
        
        [ret]=SetImage(1, 1, 1, XPixels, 1, YPixels); %   Set the image size
        CheckWarning(ret);
        
        %initalize Shamrock Spectrometer
        wait_a_second(source,eventdata,Andor_window_handle);
        [ret, nodevices]=ShamrockGetNumberDevices();
        if(ret==Shamrock.SHAMROCK_SUCCESS());
            %do nothing, already connected
        else
            [ret]=ShamrockInitialize('');
        end
        good_to_go(source,eventdata,Andor_window_handle);
        [ret, nodevices]=ShamrockGetNumberDevices();
        %we are using device 0
        [ret,SN]=ShamrockGetSerialNumber(0);
        if(~strcmp(SN,'SR2116'))
            update_andor_output(source,eventdata,'Failed to initalize spectrometer')
            return
        else
            update_andor_output(source,eventdata,'Connected to Shamrock')
            localhandles(1).Enable='on';
            localhandles(2).Enable='on';
            localhandles(12).Enable='on';
        end
        
        
        [ret,currentgrating]=ShamrockGetGrating(0);
        [ret,currentcenter]=ShamrockGetWavelength(0);
        [ret,Xcal]=ShamrockGetCalibration(0,2000);
        %save number of XPixels for later
        setappdata(main,'ShamrockGrating',currentgrating)
        setappdata(main,'ShamrockWavelength',currentcenter)
        setappdata(main,'ShamrockXCal',Xcal);
        
        %and update the drop down to show correct center wavelength and
        %grating
        localhandles(1).Value=(round(currentcenter,-1)-350)/50;
        localhandles(2).Value=currentgrating;
        
    end

    function update_andor_output(source,eventdata,newstring)
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        %add the string
        localhandles(3).String{end+1}=newstring;
        %make sure box isn't over full
        localhandles(3).String=localhandles(3).String(max([1 end-9]):end);
    end

    function change_andor_exposure_time(source,eventdata)
        temp=getappdata(main);
        if(~temp.AndorFlag)
            update_andor_output(source,eventdata,'Parameter not set!')
            beep;
            return
        end
        [ret,status]=AndorGetStatus;
        if(status~=atmcd.DRV_IDLE)
            beep;warning('Parameter not set')
            update_andor_output(source,eventdata,'Andor busy!')
            return
        end
        strstat=all(isstrprop(get(source,'string'),'digit')|isstrprop(get(source,'string'),'punct'));
        if(strstat)
            [ret]=SetExposureTime(str2num(source.String));                  %   Set exposure time in second
            CheckWarning(ret);
            update_andor_output(source,eventdata,['Integration Time: ' source.String ' s'])
        else
            source.String='15';
            beep
            update_andor_output(source,eventdata,'Numbers only in this field!')
        end
    end

    function change_andor_kinetic_time(source,eventdata)
        temp=getappdata(main);
        if(~temp.AndorFlag)
            update_andor_output(source,eventdata,'Parameter not set!')
            beep;
            return
        end
        [ret,status]=AndorGetStatus;
        if(status~=atmcd.DRV_IDLE)
            beep;warning('Parameter not set')
            update_andor_output(source,eventdata,'Andor busy!')
            return
        end
        strstat=all(isstrprop(get(source,'string'),'digit')|isstrprop(get(source,'string'),'punct'))
        if(strstat)
            [ret]=SetKineticCycleTime(str2num(source.String));           %set kinetic cycle time
            CheckWarning(ret);
            update_andor_output(source,eventdata,['Kinetic Cycle Time: ' source.String ' s']);
        else
            source.String='30';
            beep
            update_andor_output(source,eventdata,'Numbers only in this field!')
        end
    end


    function change_andor_kinetic_length(source,eventdata)
        temp=getappdata(main);
        if(~temp.AndorFlag)
            update_andor_output(source,eventdata,'Parameter not set!')
            beep;
            return
        end
        [ret,status]=AndorGetStatus;
        if(status~=atmcd.DRV_IDLE)
            beep;warning('Parameter not set')
            update_andor_output(source,eventdata,'Andor busy!')
            return
        end
        if(all(isstrprop(get(source,'string'),'digit')))
            [ret]=SetNumberKinetics(str2num(source.String));
            CheckWarning(ret);
            update_andor_output(source,eventdata,['Length of Kinetic Series: ' source.String])
        else
            source.String=5;
            beep
            update_andor_output(source,eventdata,'Numbers only in this field!')
        end
    end

    function change_andor_acquisition(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        temp=getappdata(main);
        if(~temp.AndorFlag)
            update_andor_output(source,eventdata,'Connect to Andor First!')
            beep;
            return
        end
        [ret,status]=AndorGetStatus;
        if(status~=atmcd.DRV_IDLE)
            beep;warning('Parameter not set')
            update_andor_output(source,eventdata,'Andor busy!')
            return
        end
        if(get(source,'value')==1)
            [ret]=SetAcquisitionMode(1);                  %   Set acquisition mode; 1 for single scan
            CheckWarning(ret);
            localhandles(5).Enable='off';
            localhandles(7).Enable='off';
            update_andor_output(source,eventdata,'Set to single scan mode')
        elseif(get(source,'value')==2)
            localhandles(5).Enable='on';
            localhandles(7).Enable='on';
            [ret]=SetAcquisitionMode(3);                  %   Set acquisition mode; 3 for Kinetic Series
            CheckWarning(ret);
            update_andor_output(source,eventdata,'Set to kinetic series mode')
        end
        cla(localhandles(19))
    end

    function andor_disconnect(source,eventdata)
        %stop any ongoing acquisitions
        [ret]=AbortAcquisition;
        CheckWarning(ret);
        %turn off the cooler
        [ret]=CoolerOFF;
        CheckWarning(ret);
        %close the shutter
        [ret]=SetShutter(1, 2, 1, 1);
        CheckWarning(ret);
        %shut it down
        [ret]=AndorShutDown;
        CheckWarning(ret);
        setappdata(main,'AndorFlag',0)
        update_andor_output(source,eventdata,'Disconnected from Andor')
        ShamrockClose();
        update_andor_output(source,eventdata,'Disconnected from Shamrock')
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        localhandles(1).Enable='off';
        localhandles(2).Enable='off';
        localhandles(10).Enable='on';
        localhandles(12).Enable='off';
    end

    function andor_abort_sub(source,eventdata)
        [ret]=AbortAcquisition;
        CheckWarning(ret);
        if(ret==20002)
            update_andor_output(source,eventdata,'Acquisition Aborted')
        else
            update_andor_output(source,eventdata,'Error! Acquisition not aborted!')
        end
    end

    function andor_chiller_power(source,eventdata)
        %when turning on
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        if(get(source,'value'))
            [ret]=CoolerON();
            CheckError(ret);
            source.String='Cooler On';
            %send setpoint temperature to chiller
            [ret]=SetTemperature(str2num(localhandles(15).String));
            CheckError(ret);
            %check and initalize temperature of chiller if it is on
            [ret, SensorTemp, TargetTemp, AmbientTemp, CoolerVolts]=GetTemperatureStatus();
            localhandles(13).String=[num2str(SensorTemp,'%3.1f') '�C'];
            localhandles(14).String=[num2str(TargetTemp,'%3.f') '�C'];
        else
            [ret]=CoolerOFF();
            CheckError(ret);
            source.String='Cooler Off';
        end
    end


    function andor_set_chiller_temp(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        T=str2num(source.String);
        %force T to reasonable range
        if(T<-60)
            T=-60;
        elseif(T>25)
            T=25;
        elseif(isempty(T))
            update_andor_output(source,eventdata,'Invalid temperature');
            source.String='-60';
            return
        end
        localhandles(14).String=[num2str(T,'%3.f') '�C'];
        [ret]=SetTemperature(T);
        CheckError(ret)
    end

    function update_Andor_values(source,eventdata)
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        [ret, SensorTemp, TargetTemp, AmbientTemp, CoolerVolts]=GetTemperatureStatus();
        localhandles(13).String=[num2str(SensorTemp,'%3.1f') '�C'];
        localhandles(14).String=[num2str(TargetTemp,'%3.f') '�C'];
    end

    function change_andor_wavelength(source,eventdata)
        target=source.String{source.Value};
        [ret]=ShamrockSetWavelength(0,str2num(target(1:3)));
        [ret,currentgrating]=ShamrockGetGrating(0);
        [ret,currentcenter]=ShamrockGetWavelength(0);
        [ret,Xcal]=ShamrockGetCalibration(0,2000);
        %save number of XPixels for later
        setappdata(main,'ShamrockGrating',currentgrating)
        setappdata(main,'ShamrockWavelength',currentcenter)
        setappdata(main,'ShamrockXCal',Xcal);
        update_andor_output(source,eventdata,['Center wavelength now ' target(1:3) ' nm'])
    end

    function change_andor_grating(source,eventdata)
        target=source.Value;
        [ret]=ShamrockSetGrating(0,target);
        [ret,currentgrating]=ShamrockGetGrating(0);
        [ret,currentcenter]=ShamrockGetWavelength(0);
        [ret,Xcal]=ShamrockGetCalibration(0,2000);
        %save number of XPixels for later
        setappdata(main,'ShamrockGrating',currentgrating)
        setappdata(main,'ShamrockWavelength',currentcenter)
        setappdata(main,'ShamrockXCal',Xcal);
        update_andor_output(source,eventdata,['Changed to grating number ' num2str(target)])
    end

    function andor_aqdata(source,eventdata)
        wasrunning=strcmp(fasttimer.running,'on');
        stop(fasttimer)
        stop(errorcatchtimer)
        pause(0.25)
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        [ret]=SetShutter(1, 0, 1, 1);                 %   auto Shutter
        CheckWarning(ret);
        
        
        
        %retrieve Xpixel data
        temp=getappdata(main);
        XPixels=2000;
        
        temp.AndorImage_startpointer=max([size(temp.AndorImage,2) 1]);
        setappdata(main,'AndorImage_startpointer',temp.AndorImage_startpointer);
        
        %check to ensure the number of existing timestamps and datapoints
        %matches
        if(size(temp.AndorImage,2)<length(temp.AndorTimestamp))
            %trim the number of AndorTimestamps
            update_andor_output(source,eventdata,'Warning: mismatch in existing')
            update_andor_output(source,eventdata,'timestamps and spectra!')
            update_andor_output(source,eventdata,'Trimming timestamps.')
            temp.AndorTimestamp(size(temp.AndorImage,2)+1:end)=[];
            setappdata(main,'AndorTimestamp',temp.AndorTimestamp)
            %temp.datafile.AndorTimestamp=temp.AndorTimestamp;
        elseif(size(temp.AndorImage,2)>length(temp.AndorTimestamp))
            %insert NaNs into the timestamps to preserve data
            update_andor_output(source,eventdata,'Warning: mismatch in existing')
            update_andor_output(source,eventdata,'timestamps and spectra!')
            update_andor_output(source,eventdata,'NaN-Padding timestamps.')
            if(~isempty(temp.AndorTimestamp))
                temp.AndorTimestamp(end:size(temp.AndorImage,2))=NaN;
            else
                temp.AndorTimestamp=NaN;
            end
            setappdata(main,'AndorTimestamp',temp.AndorTimestamp)
            %temp.datafile.AndorTimestamp=temp.AndorTimestamp; %check this - should the first "temp." really be there?
        end
        
        
        [ret] = StartAcquisition();
        CheckWarning(ret);
        update_andor_output(source,eventdata,'Starting Acquisition')
        
        [ret,exposed_time,~,cycle_time]=GetAcquisitionTimings;
        if(localhandles(11).Value==2) %kinetic scan
            number_exposure=str2num(localhandles(7).String);
        else
            number_exposure=1;
        end
        currenttime=clock;
        %generate a series of timestamps spaced by cycle_time
        AndorTimestamp=datenum(currenttime(1),currenttime(2),currenttime(3),currenttime(4),currenttime(5),(currenttime(6)+exposed_time/2):cycle_time:(currenttime(6)+cycle_time.*number_exposure));
        AndorCalPoly=repmat(polyfit(1:2000,temp.ShamrockXCal',2),length(AndorTimestamp),1);
        
        if(~isempty(temp.AndorTimestamp))
            temp.AndorTimestamp=[temp.AndorTimestamp AndorTimestamp];
        else
            temp.AndorTimestamp=AndorTimestamp;
        end
        
        if(~isempty(temp.AndorCalPoly))
            temp.AndorTimestamp=[temp.AndorCalPoly AndorCalPoly];
        else
            temp.AndorCalPoly=AndorCalPoly;
        end
        setappdata(main,'AndorTimestamp',temp.AndorTimestamp)
        if(wasrunning)
            start(fasttimer)
        end
        start(errorcatchtimer)
    end

    function get_andor_data(source,eventdata)
        temp=getappdata(main);
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        
        %get the number of available frames, if any
        [ret,firstimage_ind,lastimage_ind]=GetNumberNewImages;
        %get newest image when "SUCCESS" is returned
        if(localhandles(11).Value==1&&ret==atmcd.DRV_SUCCESS)
            %single scans
            [ret,AndorImage]=GetOldestImage(2000);
            %convert to unsigned 16 bit image to save space
            AndorImage=uint16(AndorImage);
            if(ret==20024)
                %no new data
                return
            end
            if(localhandles(10).Value)
                %if loop scan is checked, restart the acq.
                andor_aqdata(source,eventdata);
            else
                [ret]=SetShutter(1, 2, 1, 1);                %   close Shutter
                CheckWarning(ret);
                update_andor_output(source,eventdata,'Aquisition complete')
            end
            %                 %and save data
            if(isempty(temp.AndorImage))
                %temp.datafile.AndorImage=AndorImage;
                temp.AndorImage=AndorImage;
            else
                % temp.datafile.AndorImage(:,end+1)=AndorImage;
                temp.AndorImage(:,end+1)=AndorImage;
            end
            if(~isa(temp.AndorImage,'uint16'))
                temp.AndorImage=uint16(temp.AndorImage);
            end
            setappdata(main,'AndorImage',temp.AndorImage);
        elseif(localhandles(11).Value==2&&ret==atmcd.DRV_SUCCESS)
            if(~isa(temp.AndorImage,'uint16'))
                temp.AndorImage=uint16(temp.AndorImage);
            end
            for i=firstimage_ind:lastimage_ind
                [ret,tempimage]=GetOldestImage(2000);
                temp.AndorImage(:,temp.AndorImage_startpointer+i)=uint16(tempimage);
                CheckWarning(ret);
                update_andor_output(source,eventdata,['Got frame number ' num2str(i)])
                setappdata(main,'AndorImage',temp.AndorImage)
            end
            [ret,status]=AndorGetStatus;
            if(status==atmcd.DRV_IDLE)
                %if the device is idle, close the shutter
                [ret]=SetShutter(1, 2, 1, 1);                %   close Shutter
                CheckWarning(ret);
                update_andor_output(source,eventdata,['Aquisition complete'])
            end
        end
        
        
    end

    function update_andor_plot_1D(source,eventdata,axishandle)
        temp=getappdata(main);
        if(isempty(temp.AndorImage_startpointer))
            %do nothing
            return
        end
        if(temp.AndorImage_startpointer>=size(temp.AndorImage,2))
            %no new data to plot
            if(temp.AndorImage_startpointer~=1)
                return
            end
        end
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        cla(axishandle)
        AndorImage=temp.AndorImage(:,end);
        set(axishandle, 'XTickMode', 'auto', 'XTickLabelMode', 'auto')
        h=plot(axishandle,temp.ShamrockXCal,AndorImage);
        new_ylimits=prctile(single(AndorImage),[1 99]);
        new_ylimits(1)=new_ylimits(1)-50;
        new_ylimits(2)=new_ylimits(2)+50;
        set(axishandle,'ylim',new_ylimits);
        xlabel(axishandle,'Wavelength (nm)');
        ylabel(axishandle,'Intensity (s^{-1})');
        xlim(axishandle,[temp.ShamrockXCal(1) temp.ShamrockXCal(end)])
        dim = [.6 .6 .3 .3];
        str = ['Time: ' datestr(now)];
        %annotation(Andor_window_handle,'textbox',dim,'String',str,'FitBoxToText','on');
        xtextloc=temp.ShamrockXCal(end)-(temp.ShamrockXCal(end)-temp.ShamrockXCal(1))/2;
        ytextloc=(new_ylimits(2)*4+new_ylimits(1))/5;
        %Andor_window_handle.CurrentAxes=axishandle
        text(axishandle,double(xtextloc),double(ytextloc),str)
    end

    function update_andor_plot_2D(source,eventdata)
        two_d_plottime=tic;
        localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
        temp=getappdata(main);
        start_ind=max([temp.AndorImage_startpointer+1 1]);
        if(isempty(temp.AndorImage))
            return
        end
        %start_ind=max([1 size(temp.AndorImage,2)-keep_frames]);
        X=temp.AndorTimestamp(start_ind:size(temp.AndorImage,2));
        Y=temp.ShamrockXCal;
        Image_w_gaps=double(temp.AndorImage(:,start_ind:end));
        if(size(Image_w_gaps,2)<2)
            return
        end
        
        spacing=max([1 floor(size(Image_w_gaps,2)./500)]);
        Image_w_gaps=Image_w_gaps(:,1:spacing:end);
        X=X(1:spacing:end);
        
        %find gaps
        dX=diff(X);
        gaps=find(dX>(spacing*5/60/24)); %need to include factor of spacing to keep it from rejecting everything
        for i=fliplr(gaps)
            X=[X(1:i) NaN X(i+1:end)];
            Image_w_gaps=[Image_w_gaps(:,1:i) ones(size(Y')).*1300 Image_w_gaps(:,i+1:end)];
        end
        
        
        
        if(0)
            %   tic
            fitX=(1:2000)';
            %this is some sort of filter but TBH I have no idea how it works
            %anymore
            %TO DO: save the fitted data for subtraction? Save subtracted data
            %and append it?
            g=fittype('a1*exp(-(b1*(x-c1))^2)+a2*exp(-(b2*(x-c2))^2)+d');
            fo=fitoptions(g);
            fo.Lower=[100 100 0 0 600 600 1000];
            fo.Upper=[500 500 1 1 1400 1400 1400];
            %I think this might subtract off the constant background offset?
            fo.StartPoint=[175 175 0.005 0.005 800 800 1250];
            comp=nanmean(Image_w_gaps,2);
            fit_to_1D=fit(fitX,comp,g,fo);
            fitted=double(fit_to_1D.a1*exp(-(fit_to_1D.b1*(fitX-fit_to_1D.c1)).^2)+...
                fit_to_1D.a2*exp(-(fit_to_1D.b2*(fitX-fit_to_1D.c2)).^2)+...
                fit_to_1D.d);
            
            plotdata=(Image_w_gaps)-repmat(fitted,1,size(Image_w_gaps,2));
            %toc
        else
            %don't do background subtraction
            % tic
            plotdata=(Image_w_gaps);
            %toc
        end
        h=pcolor(localhandles(end),X,Y,plotdata);
        set(h,'linestyle','none');
        new_climits=[max([ min(min(prctile(single(plotdata),[10 95]))) 1000]) ...
            min([max(max(prctile(single(plotdata),[10 95]))) 1500])];
        
        
        set(localhandles(end),'CLimMode','manual','CLim',new_climits)
        datetick(localhandles(end),'x','HH:MM')
        xlabel(localhandles(end),'Time (HH:MM)')
        ylabel(localhandles(end),'Wavelength (nm)')
        toc(two_d_plottime);
    end

    function Andor_Realtime(source,eventdata)
       runloop=source.Value;
       temp=getappdata(main);
       localhandles=get_figure_handles(source,eventdata,Andor_window_handle);
          localhandles(1).Enable='off';
          localhandles(2).Enable='off';
          localhandles(5).Enable='off';
          localhandles(7).Enable='off';
          localhandles(9).Enable='off';
          localhandles(11).Enable='off';
          localhandles(12).Enable='off';

          if(runloop)
              %ensure auto shutter
              [ret]=SetShutter(1, 0, 1, 1);                 %   Auto Shutter
          end
        while(runloop)


           disp([datestr(now) ' Andor Realtime'])
           pause(0.01)
           
           [ret] = StartAcquisition();
           CheckWarning(ret);
           
           [ret,gstatus]=AndorGetStatus;
           CheckWarning(ret);
           while(gstatus ~= atmcd.DRV_IDLE)
               pause(0.25);
               disp('Acquiring');
               [ret,gstatus]=AndorGetStatus;
               CheckWarning(ret);
           end
           
           
           [ret, imageData] = GetMostRecentImage(2000);
           CheckWarning(ret);
           
           plot(localhandles(end),temp.ShamrockXCal,imageData)
           new_ylimits=prctile(single(imageData),[10 90]);
           new_ylimits(1)=new_ylimits(1)-10;
           new_ylimits(2)=new_ylimits(2)+20;
           set(localhandles(end),'ylim',new_ylimits);
           
           
           runloop=localhandles(10).Value;
        end
       

        localhandles(5).Enable='on';
        localhandles(7).Enable='on';
        localhandles(9).Enable='on';
        localhandles(11).Enable='on';
        if(temp.AndorFlag)
            localhandles(1).Enable='on';
            localhandles(2).Enable='on';
            localhandles(12).Enable='on';
        end
        
    end

% functions that actually do stuff for the hygrometer window

    function hygrometer_comms(source,eventdata)
        
        localhandles=get_figure_handles(source,eventdata,hygrometer_window_handle);
        if(source.Value)
            %open the connection
            
            %determine which port is selected
            
            
            portID=localhandles(2).String{localhandles(2).Value};
            
            obj3 = instrfind('Type', 'serial', 'Port', portID, 'Tag', '');
            
            if(isempty(obj3))
                obj3 = serial(portID);
            else
                fclose(obj3);
                obj3 = obj3(1);
            end
            
            
            
            obj3.Terminator={'CR/LF','CR'};
            obj3.BaudRate=38400;
            obj3.Timeout=1;
            
            fopen(obj3);
            
            %ensure that data is written upon query only
            fprintf(obj3,'$SERIALMODEQUERY ')
            b=fscanf(obj3);
            c=fscanf(obj3);
            d=fscanf(obj3);
            
            
            
            setappdata(main,'Hygrometer_comms',obj3)
            
            localhandles(2).Enable='off';
            localhandles(1).String='Port Open';
            
            %update_hygrometer_data(source,eventdata)
            
        else
            %close the connection
            temp=getappdata(main);
            if(isfield(temp,'Hygrometer_comms'))
                %close the comm and delete it from memory
                fclose(temp.Hygrometer_comms);
                rmappdata(main,'Hygrometer_comms');
            else
                %do nothing
                
            end
            
            localhandles(2).Enable='on';
            localhandles(1).String='Port Closed';
            
        end
        
    end

    function force_hygrometer_cycle(sourc,eventdata)
        temp=getappdata(main);

        flushinput(temp.Hygrometer_comms)
        fprintf(temp.Hygrometer_comms,'$ACTION 4 ')
        for i=1:2
            a=fscanf(temp.Hygrometer_comms);
        end
    end

    function force_hygrometer_heat(source,eventdata)
        temp=getappdata(main);

        flushinput(temp.Hygrometer_comms)
        fprintf(temp.Hygrometer_comms,'$ACTION 1 ')
        for i=1:2
            a=fscanf(temp.Hygrometer_comms);
        end
    end

    function force_hygrometer_normal(source,eventdata)
        temp=getappdata(main);

        flushinput(temp.Hygrometer_comms)
        fprintf(temp.Hygrometer_comms,'$ACTION 0 ')
        for i=1:2
            a=fscanf(temp.Hygrometer_comms);
        end
    end


    function update_hygrometer_data(source,eventdata,savelogic)
        
        temp=getappdata(main);
        
        
        flushinput(temp.Hygrometer_comms)
        fprintf(temp.Hygrometer_comms,'$GETDATA 0')
        for i=1:3
            a=fscanf(temp.Hygrometer_comms);
        end
        
        eqinx=strfind(a,'=');
        Td=str2num(a(eqinx+1:end));
        
        %calculate theoretical dewpoint if available
        MKShandles=get_figure_handles(source,eventdata,MKS_window_handle);
        dwpt_thy=NaN; %set a default value
        if(MKShandles(9).Data(1,2)~=-999)
            %currently assuming RT = 20 degC!
            if(isa(str2num(MKShandles(22).String),'numeric'))
                Bath_T=str2num(MKShandles(22).String);
            else
                Bath_T=19;
            end
            RH_thy=MKShandles(9).Data(1,3)/100;
            %calculate the theoretical dewpoint
            %Bath_saturation=water_vapor_pressure(source,eventdata,Bath_T+273.15);
            Trap_saturation=water_vapor_pressure(source,eventdata,MKShandles(9).Data(1,2)+273.15);
            dwpt_thy=(water_dew_pt(Trap_saturation*RH_thy)-273.15);
        end
        
        if(isempty(Td))
            Td=NaN;
        end
        
        if(~isreal(dwpt_thy)|RH_thy==0)
            dwpt_thy=NaN;
        end
        
        temp.hygrometer_data(end+1,:)=[now Td dwpt_thy];
        setappdata(main,'hygrometer_data',temp.hygrometer_data)
        update_hygrometer_plot(source,eventdata)
    end

    function update_hygrometer_plot(source,eventdata)
        temp=getappdata(main);
        localhandles=get_figure_handles(source,eventdata,hygrometer_window_handle);
        
        if(size(temp.hygrometer_data,1)>=2)
            plot(localhandles(4),temp.hygrometer_data(:,1),temp.hygrometer_data(:,2),'.',...
                temp.hygrometer_data(:,1),temp.hygrometer_data(:,3),'o')
            
            
            ylabel(localhandles(4),'Td ^\circ C')
            xlabel(localhandles(4),'Time DD HH')
            datetick(localhandles(4),'x','DD HH')
        end
        
        localhandles(3).String=[datestr(temp.hygrometer_data(end,1))...
            ' Hygrometer: ' num2str(temp.hygrometer_data(end,2)) ...
            '�C; Thy: ' num2str(temp.hygrometer_data(end,3),'%.2f') '�C'];
        
    end

end


