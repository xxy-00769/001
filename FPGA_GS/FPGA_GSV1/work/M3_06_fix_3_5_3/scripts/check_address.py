from pathlib import Path
import hashlib,json,datetime,re
root=Path(__file__).resolve().parents[1]
files=['vendor/DDR3_50H/DDR3_50H.v','rtl/reuse/fram_buf.v','rtl/board/fpga_gsv1_top.v','constraints/mes50hp.fdc']
ip=(root/files[0]).read_text(encoding='utf-8')
for name,value in [('MEM_ROW_WIDTH',15),('MEM_COLUMN_WIDTH',10),('MEM_BANK_WIDTH',3),('MEM_DQ_WIDTH',32)]:
    assert re.search(r'parameter\s+'+name+r'\s*=\s*'+str(value)+r'\b',ip),name
assert re.search(r'\.ADDR_MAPPING_SEL\s*\(1\s*\)',ip)
assert '.axi_awaddr         (axi_awaddr' in ip and '.axi_araddr         (axi_araddr' in ip
fdc=(root/files[3]).read_text(encoding='utf-8')
assert '{p:key_n[5]} {PAP_IO_LOC} {J19}' in fdc
top=(root/files[2]).read_text(encoding='utf-8')
assert 'input [5:0] key_n' in top
assert '.display_selected(!selected_view),.rd_en(read_request && !selected_view)' in top
assert '.display_selected(selected_view),.rd_en(read_request && selected_view)' in top
assert 'ENABLE_CAM' not in top
physical=set();ranges=[]
for source in range(4):
    for slot in range(2):
        first=(source<<23)|(slot<<22)
        for row in range(720):
            for beat in range(80):
                address=first+row*640+beat*8
                bank=(address>>25)&7; dram_row=(address>>10)&32767;column=address&1023
                key=(bank,dram_row,column)
                assert key not in physical
                physical.add(key)
                assert (address>>23)&3==source and (address>>22)&1==slot
        ranges.append({'Source':source,'Slot':slot,'First':hex(first),'LastBeat':hex(first+460800-8)})
out=root/'reports'/('address_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'.json')
result={'Verdict':'PASS','ConfiguredMapping':'BANK[27:25]+ROW[24:10]+COLUMN[9:0]; 32-bit word; 256-bit beat +8',
        'UniquePhysicalBeatStarts':len(physical),'SourcesVerified':4,'ProductionSources':2,'FrameSlots':2,'Ranges':ranges,
        'KEY6':'J19','OnlySelectedDisplayRead':True,'EncryptedControllerInternalSimulation':False,'BoardVerified':False,
        'Inputs':{f:hashlib.sha256((root/f).read_bytes()).hexdigest() for f in files}}
out.write_text(json.dumps(result,indent=2),encoding='utf-8')
print(out);print('ADDRESS_PASS physical_beat_starts='+str(len(physical))+' key6=J19 selected_read=1 encrypted_core_not_simulated=1')
