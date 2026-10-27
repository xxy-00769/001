# CAM0运动清晰度本轮收尾记录

用户最新反馈：“目前感觉挺好的，可以收尾了，后续如果还有提升需求再说”。按此结束本轮，不再要求下载候选、切换照明或做新一轮比较。

## 当前板上及回退

板上仍为3.5.9-R0只读版，保持原曝光，不把它标为10ms曝光优化版。用户反馈当前画面观感可接受，不外推为全部功能的新验收。

当前位流：`E:\zhoumian\FPGA\FPGA_GS\FPGA_GSV1\release\FPGA_GSV1_CAM0_OV5640_3_5_9_READBACK\FPGA_GSV1_CAM0_OV5640_3_5_9_READBACK_HDMI_1080P60.sbit`

SHA256：f760692d6a1e7695d4005945d0ba977468d8857c4b36c45dc57bd98e7283acb1

3.5.8回退：`E:\zhoumian\FPGA\FPGA_GS\FPGA_GSV1\release\FPGA_GSV1_CAM1_OV3660_3_5_8_ROTATE25_CANDIDATE\FPGA_GSV1_CAM1_OV3660_3_5_8_ROTATE25_CANDIDATE_HDMI_1080P60.sbit`

SHA256：e89ef7785f00ddfb569eb0d3754ca92b1a49a558483609ada051b3bab3c7d36a（本轮归档时复核）。后摄3.5.8仍只记录用户10秒25fps通过，未写成60秒验收。

## 已取得证据

COM23实测12秒、13条快照：ID5640；720行、921600像素；完整采集30fps、DDR发布15fps、可见显示新帧15fps；坏帧增量0、读回错误增量0。实测行周期45.04us，曝光736行=33.14944ms，增益3.5倍。HTS1892、VTS740、extra VTS0，AE/AGC自动，夜间延帧关闭。CAM0本地更新15fps和网口2上传15fps分别统计，不能混用。

长曝光与15fps本地更新是已观察到的两个因素；没有声称已独立确认静态失焦、时域降噪或所有主观拖影根因。现有FILE_TEST录像已排除，不用作前摄图像证据。

## 已实现但只归档的短曝光候选

CAM0独立cam0_ae_profile：在原OV5640模式表后确认ID，逐项读改写并完整回读，保留debug/非目标位，任何失败不放行CAM0。AE/AGC自动、222行约9.99888ms曝光上限、8倍增益上限，50Hz/60Hz步长222/185行，默认手动50Hz，禁止夜间延帧。

不修改CAM1旋转/25fps、尺寸视野、RGB565、采样沿、共享PLL、HDMI、滤镜、DDR所有权、双网口生产实现及上传15fps请求；最小读回与被动帧率统计沿用R0。关键文件为隔离work/CAM0_motion中的rtl/capture/cam0_ae_profile.v、cam0_readback.v、rtl/board/fpga_gsv1_top.v和tools/cam0；原发布包不覆盖。

生产SCCB定向检查通过：ID、所有读改写/保留位、ACK、读写超时、回读不一致、复位重配、失败不假报ready。最终综合/布局布线/真实STA通过原约束，10项快慢角汇总无失败端点；最小setup 0.022ns、hold 0.096ns。LUT22401、FF23820、DRM94.5、PLL5。未重跑无关算法、滤镜、协议历史全套。外部PHY/PCB与摄像头引脚模型限制继承，未声称重新完成电气签核。

归档版本：3.5.9 CAM0 motion candidate

归档位流：`E:\zhoumian\FPGA\FPGA_GS\FPGA_GSV1\release\FPGA_GSV1_CAM0_OV5640_3_5_9_MOTION_CANDIDATE\FPGA_GSV1_CAM0_OV5640_3_5_9_MOTION_CANDIDATE_HDMI_1080P60.sbit`

生成时间：2026-10-24T11:39:55.635820+08:00；UTC 2026-10-24T03:39:55.6358200Z

SHA256：6fe75558add3378754c8113960f59051ebe401ed8d292723b7dde0b9b4eefe0f

归档清单已核对242个文件。完整源码、资料依据、实际STA和原始串口记录均在该release。候选未下载、未实测，不替换当前可用版本；本轮不再安排后续上板。

## 未完成且本轮不再推进

没有取得优化前后同条件的真实原图/短片；未验收10ms策略实际生效及运动清晰度、暗处亮度/噪声取舍。不能声称拖影已修复。DDR/可见更新仍15fps，上传请求15fps未改变。以后用户明确提出提升需求时再从本记录和原有COM23入口继续。

回传摘要：当前原曝光画面用户认为可接受，按用户要求收尾。已实测CAM0采集30/DDR15/显示新帧15fps，曝光33.149ms、增益3.5倍，12秒坏帧0。3.5.9短曝光约10ms/8倍候选通过定向检查及PNR/STA，仅归档、未上板，不替换当前版本；3.5.8回退保留，不再要求测试。
