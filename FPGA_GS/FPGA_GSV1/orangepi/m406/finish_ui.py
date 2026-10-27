from pathlib import Path
p=Path(__file__).parent/'index.html';s=p.read_text(encoding='utf8')
s=s.replace('</span></header>', '</span></header><p class="hint">受限感知基线：夜间横排灯已有真实红/绿证据；日间远灯覆盖不足，箭头、行人灯区分及本车控制归属未完成。不以大量UNKNOWN宣称准确率。</p>')
s=s.replace('<button data-scene="change">红转绿</button>', '<button data-scene="green">夜间绿灯</button><button data-scene="change">转灯观察（可能漏检）</button>')
s=s.replace("const scenes={red:", "const scenes={green:{video:'SC_YJ.mp4',seek:107,mode:'intersection'},red:")
p.write_text(s,encoding='utf8')
