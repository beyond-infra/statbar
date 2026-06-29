#!/bin/bash
set -euo pipefail

# Generate demo.gif for README.
# Requires: node, npm (Remotion)
# Usage: ./scripts/make-demo.sh
# Output: demo.gif (repo root)

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="$REPO/statbar-demo"
OUT="$REPO/demo.gif"

if [ ! -d "$WORKDIR" ]; then
  echo "Scaffolding Remotion project..."
  npx create-video@latest --yes --blank --no-tailwind "$WORKDIR" > /dev/null 2>&1
  cd "$WORKDIR" && npm install > /dev/null 2>&1
fi

# Collect 6 seconds of real CPU data
cat << 'SWIFTEOF' > /tmp/cpu_sampler.swift
import Foundation
let pCoreCount: Int = {
    var v: Int32 = 0, s = MemoryLayout<Int32>.size
    sysctlbyname("hw.perflevel0.logicalcpu_max", &v, &s, nil, 0)
    return Int(v)
}()
func sample() -> ([Int],[Int],Int) {
    var sz: mach_msg_type_number_t = 0, info: processor_info_array_t? = nil, cnt: mach_msg_type_number_t = 0
    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cnt, &info, &sz) == KERN_SUCCESS, let info, sz >= 4 else { return ([],[],0) }
    defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(sz)*4) }
    var b: [UInt64]=[], i: [UInt64]=[]
    info.withMemoryRebound(to: UInt32.self, capacity: Int(sz)) { p in
        for c in 0..<Int(sz)/4 { let o=c*4; b.append(UInt64(p[o])+UInt64(p[o+1])); i.append(UInt64(p[o+2])) }
    }
    usleep(1_000_000)
    var info2: processor_info_array_t? = nil
    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cnt, &info2, &sz) == KERN_SUCCESS, let info2 else { return ([],[],0) }
    defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info2), vm_size_t(sz)*4) }
    var b2: [UInt64]=[], i2: [UInt64]=[]
    info2.withMemoryRebound(to: UInt32.self, capacity: Int(sz)) { p in
        for c in 0..<Int(sz)/4 { let o=c*4; b2.append(UInt64(p[o])+UInt64(p[o+1])); i2.append(UInt64(p[o+2])) }
    }
    let pc=min(pCoreCount,Int(sz)/4), ec=Int(sz)/4-pc
    func pcts(_ s: Int,_ n: Int) -> [Int] {
        (s..<(s+n)).map { let d=b2[$0]-b[$0], e=i2[$0]-i[$0], t=d+e; return t>0 ? Int(d*100/t) : 0 }
    }
    var ms=UInt32(MemoryLayout<vm_statistics64_data_t>.size/4), st=vm_statistics64_data_t()
    host_statistics64(mach_host_self(), HOST_VM_INFO64, withUnsafeMutablePointer(to:&st){$0.withMemoryRebound(to: integer_t.self, capacity:1){$0}}, &ms)
    let u=UInt64(st.internal_page_count+st.wire_count+st.compressor_page_count)*UInt64(vm_kernel_page_size)
    return (pcts(0,pc), pcts(pc,ec), ProcessInfo.processInfo.physicalMemory>0 ? Int(u*100/ProcessInfo.processInfo.physicalMemory) : 0)
}
print("[")
for i in 0..<6 {
    let (p,e,m)=sample()
    let r=(p+e+[m]).map{$0.description}.joined(separator: ",")
    print("  [\(r)]\(i<5 ? "," : "")")
    fflush(stdout)
}
print("]")
SWIFTEOF
swiftc -O -o /tmp/cpu_sampler /tmp/cpu_sampler.swift
DATA=$(/tmp/cpu_sampler)

cat > "$WORKDIR/src/Composition.tsx" << TSXEOF
import { useCurrentFrame } from "remotion";
const DATA: number[][] = $DATA;
const BW = 36, BH = 120, G = 10, MG = 20, MW = 56, RX = 8;
const barColor = (v: number) => v > 70 ? "#FF3B30" : v > 40 ? "#FF9500" : "#34C759";
export const StatbarDemo: React.FC = () => {
  const frame = Math.min(Math.floor(useCurrentFrame() / 30), 5);
  const [p0,p1,p2,p3,p4,p5,e0,e1,mem] = DATA[frame];
  const pVals = [p0,p1,p2,p3,p4,p5], eVals = [e0,e1], W = 8 * (BW + G) + MG + MW;
  return (<div style={{width:"100%",height:"100%",display:"flex",justifyContent:"center",alignItems:"center",background:"#1E1E1E"}}>
    <svg width={W+48} height={BH+48} viewBox={"-24 -24 "+(W+48)+" "+(BH+48)}>
      {Array.from({length:8}).map((_,i) => {const isP=i<6,v=isP?pVals[i]:eVals[i-6],x=i*(BW+G),fh=(v/100)*BH;
        return (<g key={i}><rect x={x} y={0} width={BW} height={BH} rx={RX} ry={RX}
          fill={isP?"rgba(0,122,255,0.3)":"rgba(142,142,147,0.3)"}/>
          {v>0&&<rect x={x} y={BH-fh} width={BW} height={fh} rx={RX} ry={RX} fill={barColor(v)}/>}</g>);})}
      <rect x={8*(BW+G)+MG} y={0} width={MW} height={BH} rx={RX} ry={RX} fill="rgba(175,82,222,0.45)"/>
      {mem>0&&<rect x={8*(BW+G)+MG} y={BH-(mem/100)*BH} width={MW} height={(mem/100)*BH} rx={RX} ry={RX}
        fill={mem>70?"#FF3B30":"#AF52DE"}/>}
      <rect x={0} y={0} width={W} height={BH} rx={16} ry={16} fill="rgba(0,0,0,0.12)"/>
    </svg></div>);
};
TSXEOF

cat > "$WORKDIR/src/Root.tsx" << TSXEOF
import "./index.css";
import { Composition } from "remotion";
import { StatbarDemo } from "./Composition";
export const RemotionRoot: React.FC = () => {
  return <><Composition id="statbar-demo" component={StatbarDemo} durationInFrames={180} fps={30} width={600} height={240}/></>;
};
TSXEOF

cd "$WORKDIR" && npx remotion render statbar-demo "$OUT" --codec=gif > /dev/null 2>&1
echo "demo.gif generated: $(ls -lh "$OUT" | awk '{print $5}')"
rm /tmp/cpu_sampler.swift /tmp/cpu_sampler 2>/dev/null || true
