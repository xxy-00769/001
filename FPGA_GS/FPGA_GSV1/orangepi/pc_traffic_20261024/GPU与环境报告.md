# GPU与环境报告

检查日期：2026-10-24，Asia/Shanghai。项目新增内容仅位于 `orangepi/pc_traffic_20261024`。硬件/已有环境只读盘点；另在本目录创建独立环境进行预检，不覆盖原依赖。

## 硬件结论

**硬件适合YOLOv8n级别的轻量微调；当前尚未具备可放行的GPU训练环境。**

|项目|实测/说明|
|---|---|
|GPU|NVIDIA GeForce RTX 4060 Laptop GPU，compute capability 8.9|
|显存|nvidia-smi总量8188MiB；初次约空闲6.4GiB，桌面占用随时间变化|
|驱动|617.14；nvidia-smi CUDA UMD 13.4；WDDM|
|系统CUDA工具链|nvcc 13.2，位于Program Files；不修改它，不因其存在就认为PyTorch可训练|
|CPU|Intel Core i7-13620H|
|内存|34,075,979,776 bytes，约31.74GiB|
|磁盘|检查时E盘约73.6GiB空闲，C盘约230.5GiB空闲；数据下载/环境会继续占用空间|
|Linux转换环境|当前WSL不可用，未安装或启用系统组件；RKNN Linux构建尚待落实|

Windows CIM的AdapterRAM仅显示约4GB，受该字段限制，**显存以nvidia-smi/CUDA Driver API的8GB为准**。

对驱动做了64MiB显存allocate→memset→synchronize→free测试，全返回0，见 `reports/cuda_driver_probe.json`。这只证明驱动与显存操作可用，不是Torch CUDA矩阵运算、AMP、训练稳定性或吞吐验证。

## 已有环境

默认Python3.9.9未安装torch/torchvision/ultralytics/onnx/onnxruntime/numpy。项目已有 `.venv`（3.9）也没有这些训练组件；`.venv312`是3.12.14，已有numpy1.26.4、opencv-python-headless4.10.0.84，没有torch/ultralytics/onnx/onnxruntime。本轮不向以上环境安装任何包。

PATH有uv和系统nvcc；未发现conda命令。py launcher列出Python3.8、3.9、uv管理的3.14；不以Python3.14作为本模型工具链起点。这里的“没有”仅指实际检查的解释器/项目环境，不代表穷举全盘所有软件。

## 本任务独立环境及限制

创建 `.venv-train`，Python3.11.15。原计划torch2.5.1+cu124/torchvision0.20.1+cu124，但CUDA wheel约2.34GiB下载持续缓慢，**已中止，未完成安装**。为了先完成ONNX结构验证，本目录改装torch2.5.1+cpu/torchvision0.20.1+cpu，配合固定Ultralytics8.3.40、numpy1.26.4、onnx1.17.0、onnxruntime1.20.1、opencv4.10.0.84。实际版本以 `reports/environment_freeze.txt`、`reports/onnx_preflight.json` 为准。

**此CPU环境不用于GPU训练；不能把torch.cuda.is_available=false解释成4060不支持训练。** 后续数据合格并准备GPU试跑时，在独立CUDA环境中安装匹配wheel，必须验证torch.version.cuda、cuda可用、实际分配、前后向及AMP；保留日志和峰值显存。无需覆盖全局CUDA或现有项目环境。

预计YOLOv8n@640从batch4、AMP开始，batch8需实测。更高分辨率或s模型以显存和细节收益为依据。笔记本功耗/散热与桌面占用会影响速度，当前没有训练耗时或GPU训练吞吐实测，不给虚构预计小时数。不得因CPU导出通过就提前开始正式训练。

原有FPGA、网络配置、香橙派服务、稳定模型均不修改；保护文件初始哈希与结束核对保存于reports。没有向板端登录或发送操作指令。
