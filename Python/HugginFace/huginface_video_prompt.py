from diffusers import TextToVideoSDPipeline
import torch

pipe = TextToVideoSDPipeline.from_pretrained("cerspense/zeroscope_v2_576w")
pipe = pipe.to("cuda")

prompt = "a cat walking"
video_frames = pipe(prompt, num_frames=24).frames