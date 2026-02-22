import numpy as np
import json
import os
from scipy.spatial.transform import Rotation as R

import sqlite3

def generate_colmap_files(json_dir, image_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    
    # Files to be created
    cameras_file = open(os.path.join(output_dir, "cameras.txt"), "w")
    images_file = open(os.path.join(output_dir, "images.txt"), "w")
    open(os.path.join(output_dir, "points3D.txt"), "w").close() # Empty file

    # Initialize Camera (Assuming all frames share one camera)
    camera_initialized = False

    # Get sorted list of JSON files
    # json_files = sorted([f for f in os.listdir(json_dir) if f.endswith('.json')])
    with open(json_file,'r') as fin:
        json_data = json.load(fin)
        
    image_id = 1 
    for idx, data in enumerate(json_data):
        # if idx % 10 != 0:
        #     extra_img = os.path.join(image_dir,f"{idx}.png")
        #     if os.path.exists(extra_img):
        #         os.remove(extra_img)
        #     continue 
        # with open(os.path.join(json_dir, json_name), 'r') as f:
        #     data = json.load(f)

        # 1. Handle Transpose (JSON is Column-Major)
        # np.array(data) interprets inner lists as rows. 
        # Since they are actually columns, we transpose to get Row-Major.
        c2w = np.array(data['transformMatrix']).T 
        intrinsics = np.array(data['intrinsicMatrix']).T

        # 2. Extract Camera Info (Once)
        if not camera_initialized:
            # ARKit Intrinsics: [fx, 0, cx], [0, fy, cy], [0, 0, 1] (after transpose)
            fx = intrinsics[0, 0]
            fy = intrinsics[1, 1]
            cx = intrinsics[2, 0] # Note: In your JSON sample, principal point was at index [2]
            cy = intrinsics[2, 1]
            w = data['imageResolution']['width']
            h = data['imageResolution']['height']
            
            cameras_file.write(f"1 PINHOLE {w} {h} {fx} {fy} {cx} {cy}\n")
            camera_initialized = True

        # 3. Transform C2W (ARKit) -> W2C (COLMAP)
        w2c = np.linalg.inv(c2w)
        
        R_w2c = w2c[:3, :3]
        T_w2c = w2c[:3, 3]

        # 4. Change Basis: Right-Handed Y-Up (ARKit) -> Right-Handed Y-Down (COLMAP)
        # Flip Y and Z axes
        flip_yz = np.diag([1, -1, -1])
        R_colmap = flip_yz @ R_w2c
        T_colmap = flip_yz @ T_w2c

        # 5. Convert to Hamilton Quaternion (w, x, y, z)
        q = R.from_matrix(R_colmap).as_quat()
        colmap_quat = [q[3], q[0], q[1], q[2]]

        # 6. Write to images.txt
        # IMAGE_ID QW QX QY QZ TX TY TZ CAMERA_ID NAME
        # image_name = json_name.replace('.json', '.png') # Adjust extension as needed
        image_loc = data.get('frameIndex', idx)
        
        
        images_file.write(f"{image_id} {' '.join(map(str, colmap_quat))} {' '.join(map(str, T_colmap))} 1 {image_loc}.png \n\n")
        image_id+=1

    cameras_file.close()
    images_file.close()
    print(f"Successfully generated sparse model files in {output_dir}")


def get_db_image_ids(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT image_id, name FROM images")
    db_map = {row[1]: row[0] for row in cursor.fetchall()}
    conn.close()
    return db_map

# Usage
if __name__ == "__main__":
    json_file = "/Users/elizabethterveen/Desktop/projects/IOS-Extrinsics-Intrinsics-Capture/parsed_videos/21_Feb_2026_02.40/video_0/calibration.json"
    images_path = "/Users/elizabethterveen/Desktop/projects/IOS-Extrinsics-Intrinsics-Capture/colmap/images"
    output_dir = "colmap/sparse"
    generate_colmap_files(json_file, images_path, output_dir)
    res = get_db_image_ids("/Users/elizabethterveen/Desktop/projects/IOS-Extrinsics-Intrinsics-Capture/colmap/database.db")
    print("done.")