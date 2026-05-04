import streamlit as st
import requests
import os

FASTAPI_URL = os.getenv('FASTAPI_URL', 'http://localhost:8000')


def set_num_items_and_payment_blocks(*args: int):
    st.session_state['num_items'] = args[0]
    st.session_state['num_payments'] = args[1]


def run_dashboard():
    st.title('Predict Time Until Second Purchase')

    st.session_state.setdefault('num_items', 1)
    st.session_state.setdefault('num_payments', 1)

    col1, col2 = st.columns(2)
    with col1:
        num_items = st.number_input(
            'Number of Items', 
            min_value=1, 
            value=st.session_state['num_items'], 
            max_value=30, 
            step=1)
    with col2:
        num_payments = st.number_input(
            'Number of Payments', 
            min_value=1, 
            value=st.session_state['num_payments'],
            max_value=30, 
            step=1)
    st.button('Generate Form', on_click=set_num_items_and_payment_blocks, args=(num_items, num_payments))

    with st.form('form', clear_on_submit=False):
        payload = fill_form()
        submitted = st.form_submit_button('Submit')
        if submitted:
            result = get_prediction(payload)
            if result is not None:
                st.success('Prediction received')
                st.json(result)


def get_prediction(payload: list[list[dict]]) -> dict | None:
    try:
        url = f'{FASTAPI_URL}/get_prediction'
        response = requests.post(url, json=payload, timeout=60)
        if response.status_code == 422:
            try:
                body = response.json()
                detail = body.get('detail', body)
                if isinstance(detail, dict):
                    st.error(detail.get('message', 'Validation failed'))
                    if detail.get('request_id'):
                        st.caption(f"request_id: {detail['request_id']}")
                    for reason in detail.get('reasons') or []:
                        st.markdown(f'- {reason}')
                else:
                    st.error(str(detail))
            except (ValueError, KeyError, TypeError):
                st.error(response.text)
            return None
        if response.status_code == 200:
            return response.json()
        st.write(f'error gay')
        st.error(f'Error {response.status_code}: {response.text}')
        return None
    except requests.exceptions.ConnectionError as e:
        st.write(f'error here')
        st.error(f'Error: {e}')
        return None
    


def fill_form() -> list[list[dict]]:
    order_level_data = {
        'request_id': st.text_input('Request ID', key='order_request_id'),
        'order_id': st.text_input('Order ID', key='order_order_id'),
        'customer_id': st.text_input('Customer ID', key='order_customer_id'),
        'customer_unique_id': st.text_input('Customer Unique ID', key='order_customer_unique_id'),
        'customer_zip': st.number_input('Customer ZIP', min_value=0, max_value=99999, value=0, key='order_customer_zip'),
        'customer_city': st.text_input('Customer City', key='order_customer_city'),
        'customer_state': st.text_input('Customer State', key='order_customer_state'),
        'order_status': st.text_input('Order Status', key='order_order_status'),
        'purchase_date': st.text_input('Purchase Date', key='order_purchase_date'),
    }
    item_level_data = []
    for i in range(st.session_state['num_items']):
        st.markdown(f'**Item {i + 1}**')
        item_level_data.append(
            {
                'request_id': order_level_data['request_id'],
                'order_id': order_level_data['order_id'],
                'item_id': st.number_input('Item ID', min_value=0, value=0, key=f'item_{i}_item_id'),
                'product_id': st.text_input('Product ID', key=f'item_{i}_product_id'),
                'seller_id': st.text_input('Seller ID', key=f'item_{i}_seller_id'),
                'shipping_limit_date': st.text_input('Shipping Limit Date', key=f'item_{i}_shipping_limit_date'),
                'price': st.number_input('Price', min_value=0.0, value=0.0, key=f'item_{i}_price'),
                'freight_value': st.number_input('Freight Value', min_value=0.0, value=0.0, key=f'item_{i}_freight_value'),
                'product_category_name': st.text_input('Product Category Name', key=f'item_{i}_product_category_name'),
                'seller_zip': st.number_input('Seller ZIP', min_value=0, max_value=99999, value=0, key=f'item_{i}_seller_zip'),
                'seller_city': st.text_input('Seller City', key=f'item_{i}_seller_city'),
                'seller_state': st.text_input('Seller State', key=f'item_{i}_seller_state'),
            }
        )

    payment_level_data = []
    for i in range(st.session_state['num_payments']):
        st.markdown(f'**Payment {i + 1}**')
        payment_level_data.append(
            {
                'request_id': order_level_data['request_id'],
                'order_id': order_level_data['order_id'],
                'payment_sequential': st.number_input(
                    'Payment Sequential', min_value=0, value=0, key=f'pay_{i}_payment_sequential'
                ),
                'payment_type': st.text_input('Payment Type', key=f'pay_{i}_payment_type'),
                'num_installments': st.number_input(
                    'Num Installments', min_value=0, value=0, key=f'pay_{i}_num_installments'
                ),
                'payment_value': st.number_input(
                    'Payment Value', min_value=0.0, value=0.0, key=f'pay_{i}_payment_value'
                ),
            }
        )

    return [[order_level_data], item_level_data, payment_level_data]


if __name__ == '__main__':
    run_dashboard()
