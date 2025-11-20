import boto3
import json
import uuid
from datetime import datetime, timezone
import random

def generate_iot_message(
    device_id: str | None = None,
    temperature: float | None = None,
    humidity: float | None = None,
    battery_mv: int | None = None,
) -> str:
    """
    Create a JSON‑formatted IoT message.

    Parameters
    ----------
    device_id : str, optional
        Unique identifier for the device. If omitted a UUID v4 is generated.
    temperature : float, optional
        Temperature reading (°C). If omitted a random value is used (demo).
    humidity : float, optional
        Relative humidity (%). If omitted a random value is used (demo).
    battery_mv : int, optional
        Battery voltage in millivolts. If omitted a random value is used (demo).

    Returns
    -------
    str
        JSON string ready to be sent over MQTT, HTTP, CoAP, etc.
    """

    # Fill missing values with sensible defaults (or random demo data)
    if device_id is None:
        device_id = str(uuid.uuid4())
    if temperature is None:
        temperature = round(random.uniform(15.0, 30.0), 2)
    if humidity is None:
        humidity = round(random.uniform(30.0, 70.0), 2)
    if battery_mv is None:
        battery_mv = random.randint(3000, 4200)

    payload = {
        "deviceId": device_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "temperatureC": temperature,
        "humidityPct": humidity,
        "batteryMv": battery_mv,
    }

    # Convert dict to compact JSON string (no whitespace)
    return json.dumps(payload)



def lambda_handler(event, context):
    # Create IoT Data client
    iot_client = boto3.client('iot-data')
    
    message = generate_iot_message(device_id="sensor-001")

    response = iot_client.publish(
        topic='iot/data',
        qos=0,
        payload=message
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps('Message published successfully')
    }
