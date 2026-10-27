"""CPU geometry baseline; no pretrained model and no frame-number decisions."""
import time
import cv2
import numpy as np

DEFAULT = dict(signal_roi=[.05,.03,.95,.55], signal_actions=[],
               lane_geometry_confirmed=False,
               road_quad=[[.4,.58],[.6,.58],[.95,.96],[.05,.96]])

def runs(values):
    edges = np.diff(np.r_[False, values, False].astype(np.int8))
    return list(zip(np.where(edges == 1)[0], np.where(edges == -1)[0]))

def decide(observation, action):
    if action == 4:
        return dict(code=1, reason=0, explanation='STOP_INTENT_NO_RED_VIOLATION')
    if action not in (1,2,3):
        return dict(code=0, reason=0, explanation='INVALID_INTENT')
    light = observation['signal']
    relevant = action in light['actions'] and light.get('confidence',0)>=.7
    if relevant and light['state'] == 'RED':
        return dict(code=2, reason=1, explanation='RED_LIGHT_SIMULATED_ACTION_WARNING')
    if not relevant or light['state'] != 'GREEN':
        return dict(code=0, reason=0, explanation='SIGNAL_STATE_OR_ASSOCIATION_UNCERTAIN')
    side = 'left' if action == 1 else 'right'
    if action in (1,2):
        boundary = observation['lanes'][side]
        if boundary['state'] == 'SOLID' and boundary.get('confidence',0)>=.7:
            return dict(code=2, reason=2, explanation=side.upper()+'_SOLID_SIMULATED_ACTION_WARNING')
        if boundary['state'] != 'DASHED' or boundary.get('confidence',0)<.7:
            return dict(code=0, reason=0, explanation='BOUNDARY_UNCERTAIN')
    return dict(code=1, reason=0, explanation='GREEN_AND_REQUIRED_BOUNDARY_CLEAR')

class Vision:
    def __init__(self, config=None):
        self.config = dict(DEFAULT, **(config or {}))
        cv2.setNumThreads(2)

    def signal(self, image, overlay):
        h,w = image.shape[:2]
        x0,y0,x1,y1 = (np.array(self.config['signal_roi'])*[w,h,w,h]).astype(int)
        crop = image[y0:y1,x0:x1]
        hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
        candidates = []
        for state, ranges in [('RED',[(0,10),(170,179)]), ('GREEN',[(42,92)]), ('AMBER',[(15,37)])]:
            mask = np.zeros(hsv.shape[:2], np.uint8)
            for low, high in ranges:
                mask |= cv2.inRange(hsv, (low,115,140), (high,255,255))
            contours,_ = cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
            for contour in contours:
                area = cv2.contourArea(contour)
                x,y,bw,bh = cv2.boundingRect(contour)
                perimeter = cv2.arcLength(contour, True)
                if not (8 <= area <= w*h*.002 and .65 < bw/max(1,bh) < 1.5 and
                        perimeter and 4*np.pi*area/perimeter**2 > .62):
                    continue
                # Require a dark vertical signal housing surrounding the luminous disk.
                radius = max(bw,bh)
                cx,cy = x+bw//2,y+bh//2
                a,b = max(0,cx-radius),min(crop.shape[1],cx+radius+1)
                c,d = max(0,cy-3*radius),min(crop.shape[0],cy+3*radius+1)
                surround = hsv[c:d,a:b,2]
                if surround.size == 0 or np.mean(surround < 95) < .62 or d-c < 4*radius:
                    continue
                # A dark neighborhood alone also matches trees/signs. Require an
                # isolated, elongated dark housing enclosing the luminous disk.
                xa,xb=max(0,cx-3*radius),min(crop.shape[1],cx+3*radius)
                ya,yb=max(0,cy-7*radius),min(crop.shape[0],cy+7*radius)
                dark=(hsv[ya:yb,xa:xb,2]<95).astype(np.uint8)*255
                dark=cv2.morphologyEx(dark,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
                housings,_=cv2.findContours(dark,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
                enclosed=False
                for housing in housings:
                    hx,hy,hw,hh=cv2.boundingRect(housing)
                    if (hx<cx-xa<hx+hw and hy<cy-ya<hy+hh and
                        1.25*radius<hw<3.8*radius and 3.5*radius<hh<9*radius and
                        .18<hw/hh<.6 and hx>0 and hy>0 and hx+hw<xb-xa and hy+hh<yb-ya and
                        cv2.contourArea(housing)/(hw*hh)>.65):
                        enclosed=True; break
                if not enclosed: continue
                rect=[int(x+x0),int(y+y0),int(bw),int(bh)]
                candidates.append(dict(state=state,box=rect,confidence=.75))
                cv2.rectangle(overlay,tuple(rect[:2]),(rect[0]+bw,rect[1]+bh),(0,180,255),2)
        # Multiple lit candidates may be different lanes, arrows or background lights.
        state = candidates[0]['state'] if len(candidates)==1 else 'UNKNOWN'
        return dict(state=state,confidence=.75 if state!='UNKNOWN' else 0,
                    actions=self.config['signal_actions'],candidates=candidates,
                    association='SIMULATION_SCENE_CONFIGURATION' if self.config['signal_actions'] else 'UNASSIGNED')

    def lanes(self, image, overlay):
        h,w=image.shape[:2]
        quad=np.float32(self.config['road_quad'])*[w,h]
        matrix=cv2.getPerspectiveTransform(quad.astype(np.float32),np.float32([[0,0],[319,0],[319,239],[0,239]]))
        inverse=np.linalg.inv(matrix)
        road=cv2.warpPerspective(image,matrix,(320,240))
        hsv=cv2.cvtColor(road,cv2.COLOR_BGR2HSV)
        contrast=cv2.morphologyEx(hsv[:,:,2],cv2.MORPH_TOPHAT,np.ones((15,31),np.uint8))
        white=cv2.inRange(hsv,(0,0,105),(179,90,255)) & ((contrast>18)|(hsv[:,:,2]>190)).astype(np.uint8)*255
        mask=white | cv2.inRange(hsv,(15,80,110),(38,255,255))
        mask=cv2.morphologyEx(mask,cv2.MORPH_OPEN,np.ones((3,2),np.uint8))
        result={}
        for side,lo,hi in [('left',12,155),('right',165,308)]:
            histogram=(mask[:,lo:hi]>0).sum(axis=0)
            peak=int(np.argmax(histogram))+lo
            centers=[]
            for ya in range(0,240,12):
                yy,xx=np.where(mask[ya:ya+12,max(lo,peak-12):min(hi,peak+13)]>0)
                if len(xx)>=12:
                    centers.append((float(np.median(xx)+max(lo,peak-12)),ya+6))
            state='UNKNOWN'; confidence=0.; coverage=0.; segments=[]
            if len(centers)>=5:
                pts=np.array(centers)
                fit=np.polyfit(pts[:,1],pts[:,0],1)
                residual=float(np.sqrt(np.mean((np.polyval(fit,pts[:,1])-pts[:,0])**2)))
                y=np.arange(240); x=np.polyval(fit,y).astype(int)
                occupied=np.array([np.count_nonzero(mask[v,max(0,u-4):min(320,u+5)])>=2 for u,v in zip(x,y)])
                # Fill <=3px pinholes; leave real longitudinal gaps intact.
                occupied=cv2.morphologyEx(occupied.astype(np.uint8).reshape(-1,1),cv2.MORPH_CLOSE,np.ones((4,1),np.uint8)).ravel()>0
                segments=[(a,b) for a,b in runs(occupied) if b-a>=8]
                gaps=[(a,b) for a,b in runs(~occupied) if b-a>=10 and a>0 and b<240]
                coverage=float(np.mean(occupied))
                if residual<7 and .35<peak/320<.65:
                    pass  # close-to-center markings remain ambiguous
                elif residual<7 and self.config['lane_geometry_confirmed']:
                    if coverage>.85 and not gaps: state='SOLID'; confidence=.8
                    elif .22<coverage<.76 and len(segments)>=3 and len(gaps)>=2:
                        state='DASHED'; confidence=.7
                trace=np.float32([[[float(np.polyval(fit,v)),float(v)]] for v in range(0,240,10)])
                original=cv2.perspectiveTransform(trace,inverse).astype(int)
                cv2.polylines(overlay,[original],False,(0,255,0) if state!='UNKNOWN' else (128,128,128),2)
            result[side]=dict(state=state,confidence=confidence,coverage=round(coverage,3),segments=len(segments))
        cv2.polylines(overlay,[quad.astype(int)],True,(100,100,100),1)
        return result

    def analyze(self, image):
        start=time.perf_counter(); overlay=image.copy()
        result=dict(signal=self.signal(image,overlay),lanes=self.lanes(image,overlay))
        result['inference_ms']=round((time.perf_counter()-start)*1000,3)
        result['decisions']={str(action):decide(result,action) for action in (1,2,3,4)}
        return result,overlay
