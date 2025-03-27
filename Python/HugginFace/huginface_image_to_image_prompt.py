from diffusers import StableDiffusionPipeline
import torch

model_id = "sd-legacy/stable-diffusion-v1-5"
pipe = StableDiffusionPipeline.from_pretrained(model_id, torch_dtype=torch.float16)
pipe = pipe.to("cuda")

prompt = "A picture of a dog on the beach on a motorcycle"
image = pipe(prompt).images[0]  
    
image.save("astronaut_rides_horse.png")