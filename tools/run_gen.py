# Generates the run clip from WORLD angles (deg from straight down, + = forward) read off the reference GIF.
import math
c=math.cos; r=math.radians
# per half-step key: contact, down, pass, drive.  A = right leg leads.
T    =[-28,-42,-55,-52]          # torso pitch
HEAD =[18,28,40,32]
HIPY =[-12,-6,0,10]; TORY=[22,12,0,-18]
LEAD =[(45,36),(25,-55),(-25,-55),(-45,-45)]     # leading leg (thigh, shin) world
FREE =[(-60,-160),(-30,-150),(70,-15),(98,0)]    # other leg
# sword arm R over full cycle (8 keys), (upper, fore) world, + blade target
SW   =[(-150,-95,-100),(-125,-60,-105),(-70,10,-110),(-15,100,-125),(0,120,-130),(-20,100,-125),(-90,-10,-110),(-140,-90,-100)]
# free arm L full pump (8 keys)
AL   =[(30,165),(15,150),(-40,60),(-135,-100),(-150,-95),(-130,-70),(-60,40),(40,150)]
CAPE =[(-100,-20,20),(-90,-35,-25),(-85,-10,30),(-105,15,-20)]
def sole(t,s,hip): return hip-0.1-0.5*c(r(t))-0.56*c(r(s))
HIP=[]
for k,(t,s) in enumerate(LEAD):
    h=0.1+0.5*c(r(t))+0.56*c(r(s)); HIP.append(round(h+(0.08 if k==3 else 0.0),3))
print("hips",HIP)
prevS=None; lines=[]
for i in range(8):
    k=i%4; A=i<4
    lead,free=("R","L") if A else ("L","R")
    t=T[k]; sgn=1 if A else -1
    d={}
    d["@Hips"]=f"Vector3(0, {HIP[k]}, 0)"
    d["Hips"]=f"Vector3(0, {HIPY[k]*sgn}, 0)"
    d["Torso"]=f"Vector3({t}, {TORY[k]*sgn}, 0)"
    d["Head"]=f"Vector3({HEAD[k]}, {-TORY[k]*sgn//2}, 0)"
    lt,ls=LEAD[k]; ft,fs=FREE[k]
    d["UpperLeg"+lead]=f"Vector3({lt}, 0, 0)"; d["LowerLeg"+lead]=f"Vector3({ls-lt}, 0, 0)"
    d["UpperLeg"+free]=f"Vector3({ft}, 0, 0)"; d["LowerLeg"+free]=f"Vector3({fs-ft}, 0, 0)"
    u,f,tg=SW[i]; S=tg-f
    if prevS is not None:
        while S-prevS>180: S-=360
        while S-prevS<-180: S+=360
    prevS=S
    d["UpperArmR"]=f"Vector3({u-t}, 0, -10)"; d["LowerArmR"]=f"Vector3({f-u}, 0, 0)"; d["Sword"]=f"Vector3({S}, 0, 0)"
    u,f=AL[i]
    d["UpperArmL"]=f"Vector3({u-t}, 0, 10)"; d["LowerArmL"]=f"Vector3({f-u}, 0, 0)"
    c0,c1,c2=CAPE[k]
    d["Cape0"]=f"Vector3({c0-t}, 0, 0)"; d["Cape1"]=f"Vector3({c1}, 0, 0)"; d["Cape2"]=f"Vector3({c2}, 0, 0)"
    print(i, "lead sole", round(sole(lt,ls,HIP[k]),3), "free sole", round(sole(ft,fs,HIP[k]),3), "S",S)
    lines.append(d)
lines.append(lines[0])
names=["contact","down","pass","drive"]
out=[]
for i,d in enumerate(lines):
    tag=f"{names[i%4]} {'R' if (i%8)<4 else 'L'}" if i<8 else "loop"
    body=", ".join(f'"{k}": {v}' for k,v in d.items())
    out.append(f"\t\t[{i*0.08:.2f}, {{{body}}}],   # {tag}")
open(__file__.replace("run_gen.py","run_keys.txt"),"w").write("\n".join(out)+"\n")
