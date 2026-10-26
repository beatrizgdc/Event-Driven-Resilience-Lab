import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info("Iniciando processamento do evento SQS...")
    
    for record in event.get('Records', []):
        body = record.get('body', '{}')
        logger.info(f"Conteudo do registro SQS recebido: {body}")
        
        try:
            message_json = json.loads(body)
            
            if 'Records' in message_json:
                for s3_record in message_json['Records']:
                    object_key = s3_record['s3']['object']['key']
                    logger.info(f"Arquivo detectado no S3: {object_key}")
                    
                    if "invalid" in object_key or "fail" in object_key:
                        logger.error(f"[FAILURE INJECTION] Erro provocado no processamento de: {object_key}")
                        raise RuntimeError(f"Erro simulado ao processar arquivo instável: {object_key}")
                        
            logger.info("Registro processado com sucesso!")
            
        except json.JSONDecodeError:
            logger.warning("Mensagem não está em formato JSON válido.")
            
    return {
        'statusCode': 200,
        'body': json.dumps('Eventos processados com sucesso!')
    }
