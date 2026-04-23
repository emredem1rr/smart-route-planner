from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .routers.optimize        import router as optimize_router
from .routers.benchmark       import router as benchmark_router
from .routers.suggest         import router as suggest_router
from .routers.personalize     import router as personalize_router
from .routers.real_world_case import router as real_world_router

app = FastAPI(title='Smart Route Optimizer')

app.add_middleware(
    CORSMiddleware,
    allow_origins     = ['*'],
    allow_credentials = True,
    allow_methods     = ['*'],
    allow_headers     = ['*'],
)

app.include_router(optimize_router)
app.include_router(benchmark_router)
app.include_router(suggest_router)
app.include_router(personalize_router)
app.include_router(real_world_router)

@app.get('/health')
async def health():
    return {'status': 'ok'}