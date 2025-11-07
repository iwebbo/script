import torch
from diffusers import StableDiffusionXLImg2ImgPipeline
from diffusers.utils import load_image

pipe = StableDiffusionXLImg2ImgPipeline.from_pretrained(
    "stabilityai/stable-diffusion-xl-refiner-1.0", torch_dtype=torch.float16, variant="fp16", use_safetensors=True
)
pipe = pipe.to("cuda")
url = "https://huggingface.co/datasets/patrickvonplaten/images/resolve/main/aa_xl/000000009.png"

init_image = load_image(url).convert("RGB")
prompt = "Create a detailed architecture diagram of a Kubernetes-native monitoring platform named THEAI: - Kubernetes Cluster with nodes (baremetal and virtualized) - Helm managing deployments: Frontend (React + Nginx), Backend (FastAPI), PostgreSQL with PVC - CI/CD Pipeline showing: - Code repo pushing to Docker registry - Jenkins or GitHub Actions building images, running tests - Helm upgrade/install step - Kubectl rollout restart to refresh deployments - Frontend accesses Backend API via Nginx reverse proxy configured with ConfigMap - Backend connects securely to PostgreSQL service using K8s Secrets - Services exposed as NodePort for frontend and backend - Include arrows for traffic flow and automated deployment triggers - Style: professional, clear, modern cloud-native diagram"
image = pipe(prompt, image=init_image).images