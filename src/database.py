from sqlalchemy import create_engine
import os
from dotenv import load_dotenv
import pandas as pd
from contextlib import contextmanager
from sqlalchemy.engine import URL
import psycopg2 

load_dotenv() # move this to main.py later or main entry point

class Database:
    """Class which manages queries to and from database"""
    def __init__(self, dbname: str, dbuser: str, dbpassword: str, host: str = 'localhost', port: int = 5432):
        """Initialize a database manager"""
        self.connection_url = URL.create(drivername='postgresql+psycopg2', username=dbuser, password=dbpassword, host=host, port=port, database=dbname)
        self.engine = create_engine(self.connection_url)

    @contextmanager
    def connect_to_database(self):
        """Create a connection to the database via URL"""
        conn = self.engine.connect()
        try:
            yield conn
        finally:
            conn.close()

    def load_query(self, sql, params = None):
        """Load data from db into a df in memory"""
        with self.connect_to_database() as conn:
            df = pd.read_sql_query(sql, conn, params=params)
            return df
    
    def minibatch_load_data(self, sql, limit = 10000, offset = 0, params = None) -> pd.DataFrame:
        """Load mini-batches of data from db into a df in memory"""
        query = f"{sql} LIMIT {limit} OFFSET {offset}"
        with self.connect_to_database() as conn:
            return pd.read_sql_query(query, conn, params=params)
        
    def iterate_batches(self, sql, batchsize=1000, params=None):
        """Yield DataFrames of at most ``batchsize`` rows (LIMIT/OFFSET). 
        Use when the SQL result is too large for a single ``load_query``; 
        training still typically builds one snapshot or sample from these chunks."""
        offset = 0
        while True:
            batch = self.minibatch_load_data(sql, batchsize, offset, params)
            if batch.empty:
                break

            yield batch

            offset += batchsize

            del batch

    def pandas_to_sql(self, user_input: pd.Series | pd.DataFrame, table_name: str):
        """Convert pandas df to sql"""
        # some error handling here
        user_input.to_sql(name=table_name, con=self.engine, if_exists='append', index=False)

    def execute(self, sql, params = None):
        """Execute sql queries to the connected database"""
        with self.connect_to_database() as conn:
            result = conn.execute(sql, parameters=params or ())
            conn.commit()
            return result.rowcount

def create_database_manager() -> Database:
    """Create a database manager"""
    dbname = os.getenv('DATABASENAME')
    dbuser = os.getenv('DBUSER', 'postgres')
    dbpassword = os.getenv('DBPASSWORD')
    dbhost = os.getenv('DBHOST', 'localhost')
    dbport = os.getenv('DBPORT', 5432)

    return Database(dbname, dbuser, dbpassword, dbhost, dbport)
