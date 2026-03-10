import json 
import av
import numpy as np
import glob
import os
from pathlib import Path
from datetime import datetime
import cv2 as cv
import re 
from tqdm import tqdm

def load_json(fp):
    with open(fp,'r') as fin:
        js = json.load(fin)
    return js 

def load_video(fp, calibration_data = None):
    container = av.open(fp)
    if calibration_data is not None:
        start_time = calibration_data['sessionStartTime']
    rgb = []
    for idx,frame in enumerate(container.decode(video=0)):
        # This 'time' is the exact value of the 'ts' variable 
        # you passed to the pixelBufferAdaptor in Swift.
        
        frame_rgb = frame.to_ndarray(format="rgb24")
        rgb.append(frame_rgb)

        
        # check that this is a sensible match
        if calibration_data is not None:
            abs_ts = frame.time + start_time
            assert abs(abs_ts-calibration_data['frames'][idx]['timestamp']) < 1e-3
            assert abs(timestamps[idx]-calibration_data['frames'][idx+1]['timestamp']) > 1e-2
            assert abs(timestamps[idx]-calibration_data['frames'][idx-1]['timestamp']) > 1e-2
        
    return rgb

def get_paired_data(root_dir,video_ext="mp4"):
    names = set()
    all_fps = os.listdir(root_dir)
    for fp in all_fps:
       path = Path(fp) 
       name = path.stem 
       name = name.replace("_calibration","")
       
       calib_fp = f'{name}_calibration.json'
       vid_fp = f'{name}.{video_ext}'
       
       if (calib_fp in all_fps) and (vid_fp in all_fps) and name not in names:
           names.add(name)
           yield os.path.join(root_dir,calib_fp), os.path.join(root_dir,vid_fp) 
       
    

def main(args):
    outdir = os.path.join(args.outdir,datetime.now().strftime("%d_%b_%Y_%I.%M"))
    os.makedirs(outdir,exist_ok=True)
    data_pairs = get_paired_data(args.root_dir)
    
    
    
    for idx, (calibration_fp, video_fp) in tqdm(enumerate(data_pairs)):
        calibration_json = load_json(calibration_fp)
        video_rgb = load_video(video_fp)
        
        video_outdir = os.path.join(outdir,f'video_{idx}')
        os.makedirs(video_outdir,exist_ok=True)
        
        # write json data 
        with open(os.path.join(video_outdir,"calibration.json"),'w') as fout:
            json.dump(calibration_json['frames'],fp=fout)
        
        # write video data
        for idx,frame in enumerate(video_rgb):
            
            frame_path = os.path.join(video_outdir,f"{idx}.png")
            frame = cv.cvtColor(frame, cv.COLOR_RGB2BGR)
            frame = cv.rotate(frame, cv.ROTATE_90_CLOCKWISE)
            if idx == 0:
                print(f"[DEBUG] {frame.shape}")
            cv.imwrite(frame_path,frame)
  
if __name__ == "__main__":     
    import argparse 
    
    parser = argparse.ArgumentParser()
    
    parser.add_argument("--root_dir", "-d", required=True,help = "directory with calibration / video pairs")  
    parser.add_argument("--outdir", "-o", help = "save location",default="parsed_videos")  
    
    args = parser.parse_args()
    main(args)      