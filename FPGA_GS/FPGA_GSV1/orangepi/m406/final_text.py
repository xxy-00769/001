from pathlib import Path
p=Path(__file__).parent/'index.html';s=p.read_text(encoding='utf8').replace('Hz / 交通灯目标4Hz','Hz / 交通灯目标4Hz（左右交替，每侧约一半；逐灯另计）');s=s.replace('新灯态连续两次确认，变化时先不可判','新灯态连续两次确认，变化时先不可判；成对灯壳支持最长1.2秒原图匹配跟踪，每帧重新复查灯色，非沿用旧灯色');p.write_text(s,encoding='utf8')
