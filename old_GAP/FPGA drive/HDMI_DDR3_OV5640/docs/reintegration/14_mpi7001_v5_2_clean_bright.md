# V5.2 MPI7001 显示调整

用户反馈 V5.1 上板显示稳定，画面稍暗，要求移除彩边。本轮以该稳定版本为基线，仅改显示输出。

- 删除顶部彩条和底部棋盘，边缘恢复黑色，中央画面保持 640×360，面板仍为 800×480、约 59.93Hz。
- HDMI 输出前将 RGB565 通过高位复制展开为 RGB888，再对三通道统一施加 9/8 增益，超过 255 封顶。黑色不抬升。该增益会使接近白色的区域更早饱和，现场观感需用户确认。
- 保留 V5.1 首帧同步修复、输出寄存器及控制信号延迟。
- 不改变算法、摄像头配置、DDR、KEY8 模式、PLL 和 FDC。

范围证据：E:/zhoumian/FPGA/JF/checks/v5_2_scope/scope.json 与 diff.txt。仅 hdmi_ddr_ov5640_top.v、mpi7001_timing.v 两份源文件相对 V5.1 改动。

显示输出检查：E:/zhoumian/FPGA/JF/checks/v5_2_output_20261020_140317，PASS、InputsUnchanged=true。从实际顶层提取输出函数及寄存器块，验证全部 65536 个 RGB565 输入及 8 种使能组合，核对饱和增益、黑边和控制信号对齐；另外核对三整帧屏幕几何、极性、启动与空白背景。不属于算法验证或物理 HDMI 验收。

完整编译：第二轮 PASS，最终报告 All Constraints Met，InputsUnchanged=true。未由代理烧录或写 Flash。

首轮构建 `JF/builds/v5_2_20261020_140244` 返回码为零并生成位流，但最终 fast hold 有 −0.005ns（旧 base_delay 寄存器短路径），发布门槛判为失败，未交付。第二轮仅将布局种子 4 改为 5，源 RTL 与 FDC 不变。

最终构建：`E:/zhoumian/FPGA/JF/builds/v5_2_20261020_140727`。SHA256：`7EA20831607DC5269D8C75C04B64FC289C1D2D99898839C6336794E44B42F050`。交付 `E:/zhoumian/FPGA/JF/V5_2_MPI7001_800x480_BRIGHT/V5_2_MPI7001_BRIGHT_KEY8_cmos1.sbit`，未上板验证。
