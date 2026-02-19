import json 
import av
import numpy as np
import glob
import os
from pathlib import Path
from datetime import datetime
import cv2 as cv
import re 

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
        if idx == 0:
            print(frame_rgb.shape)
        
        # check that this is a sensible match
        if calibration_data is not None:
            abs_ts = frame.time + start_time
            assert abs(abs_ts-calibration_data['frames'][idx]['timestamp']) < 1e-3
            assert abs(timestamps[idx]-calibration_data['frames'][idx+1]['timestamp']) > 1e-2
            assert abs(timestamps[idx]-calibration_data['frames'][idx-1]['timestamp']) > 1e-2
        
    return rgb

def get_paired_data(root_dir,video_ext="mp4"):
    names = set()
    for fp in os.listdir(root_dir):
       path = Path(fp) 
       name = path.stem 
       name = name.replace("_calibration","")
       names.add(name)
    
    
    return [(os.path.join(root_dir,f'{name}.json'),os.path.join(root_dir,f'{name}.{video_ext}')) for name in names ]
    

def main():
    root_dir = '/Users/elizabethterveen/Desktop/lpwm.ExInt-Capture-2 2026-02-19 10:17.24.843.xcappdata/AppData/Documents'
    outdir = os.path.join("parsed_videos",datetime.now().strftime("%d_%b_%Y_%I.%M"))
    os.makedirs(outdir,exist_ok=True)
    data_pairs = get_paired_data(root_dir,video_ext='mov')
    for idx, (calibration_fp, video_fp) in enumerate(data_pairs):
        calibration_json = load_json(calibration_fp)
        video_rgb = load_video(video_fp)
        
        video_outdir = os.path.join(outdir,f'video_{idx}')
        os.makedirs(video_outdir,exist_ok=True)
        
        # write json data 
        with open(os.path.join(video_outdir,"calibration.json"),'w') as fout:
            json.dump(calibration_json,fp=fout)
        
        # write video data
        for idx,frame in enumerate(video_rgb):
            frame_path = os.path.join(video_outdir,f"{idx}.png")
            frame = cv.cvtColor(frame, cv.COLOR_RGB2BGR)
            frame = cv.rotate(frame, cv.ROTATE_90_CLOCKWISE)
            cv.imwrite(frame_path,frame)
  
if __name__ == "__main__":        
    main()      