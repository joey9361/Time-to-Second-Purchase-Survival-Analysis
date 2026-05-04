# Fast api
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.exc import IntegrityError
from src.serve import RejectedInputError, create_online_serving, get_categorical_options
from src.model import load_model
import os

load_dotenv()


class Prediction(BaseModel):
    request_id: str
    risk_score: float
    # None when S(t) never crosses 0.5 on the fitted horizon (see model.median_survival_days).
    median_days_until_second_purchase: float | None
    restricted_mean_survival_days: float
    note: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load the survival model once when the process starts; reuse for every request."""
    model_path = os.getenv("MODEL_PATH")
    if not model_path:
        raise RuntimeError("MODEL_PATH is not set")
    app.state.model = load_model(model_path)
    yield
    app.state.model = None


app = FastAPI(lifespan=lifespan)

@app.get('/get_option_categories')
def get_option_categories(): 
    state_options, product_category_options, payment_type_options = get_categorical_options()
    states = state_options.iloc[:, 0].tolist()
    product_categories = product_category_options.iloc[:, 0].tolist()
    payment_types = payment_type_options.iloc[:, 0].tolist()
    return {
        'state_options': states,
        'product_category_options': product_categories,
        'payment_type_options': payment_types
    }
    return 
@app.post("/get_prediction", response_model=Prediction)
def get_prediction(body: list[list[dict]], request: Request):
    """
    Body matches Streamlit: [[order_dict], [item_dict, ...], [payment_dict, ...]].
    """
    model = request.app.state.model
    
    try:
        prediction = create_online_serving(body, model)
    except RejectedInputError as e:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "Input data failed validation (rejected rows).",
                "request_id": e.request_id,
                "reasons": e.reasons,
            },
        ) from e
    except ValueError as e:
        raise HTTPException(
            status_code=422,
            detail={"message": str(e), "request_id": None, "reasons": []},
        ) from e
    except IntegrityError as e:
        raw = str(e.orig) if getattr(e, "orig", None) is not None else str(e)
        # New request_id reusing an order_id that already committed on another row (final_user_orders.order_id UNIQUE).
        if "final_user_orders_order_id_key" in raw:
            raise HTTPException(
                status_code=422,
                detail={
                    "message": (
                        "This order_id is already stored from a previous successful run "
                        "(order_id is unique across all requests). Use a new order_id for this request_id, "
                        "or use the same request_id as before if you intend to update that request."
                    ),
                    "request_id": None,
                    "reasons": [raw],
                },
            ) from e
        # Child rows reference final_user_orders.order_id; changing only the parent's order_id breaks FK.
        if (
            "final_user_order_items_order_id_fkey" in raw
            or "final_user_payments_order_id_fkey" in raw
        ):
            raise HTTPException(
                status_code=422,
                detail={
                    "message": (
                        "Cannot change order_id for this request_id: items and/or payments in the database "
                        "still reference the previous order_id (foreign key). Keep the same order_id when "
                        "fixing other fields, or reset/clear online tables and submit as a new request."
                    ),
                    "request_id": None,
                    "reasons": [raw],
                },
            ) from e
        raise HTTPException(
            status_code=422,
            detail={
                "message": "Database constraint violation; check identifiers and try again.",
                "request_id": None,
                "reasons": [raw],
            },
        ) from e
    return Prediction(**prediction)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "api:app",  # Replace 'your_filename' with your actual filename
        host=os.getenv("FASTAPI_HOST", '127.0.0.1'),
        port=int(os.getenv("FASTAPI_PORT", '8000')),
        reload=os.getenv("DEBUG_MODE", True)  # Auto-reload when DEBUG=True
    ) 
    pass