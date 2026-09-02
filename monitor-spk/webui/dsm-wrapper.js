Ext.ns('NvidiaGpuMonitor');
Ext.define('NvidiaGpuMonitor.AppInstance',{extend:'SYNO.SDS.AppInstance',appWindowName:'NvidiaGpuMonitor.AppWindow'});
Ext.define('NvidiaGpuMonitor.AppWindow',{extend:'SYNO.SDS.AppWindow',constructor:function(config){this.callParent([Ext.apply({resizable:true,maximizable:true,minimizable:true,width:760,height:760,minWidth:520,minHeight:560,layout:'fit',border:false,items:[{xtype:'box',autoEl:{tag:'iframe',src:'/webman/3rdparty/SynoNvidiaGpuMonitor/index.html',frameborder:'0',style:'width:100%;height:100%;border:none;'}}]},config)]);}});
