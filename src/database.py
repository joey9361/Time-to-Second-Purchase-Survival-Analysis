from sqlalchemy import create_engine, text
import os
import pandas as pd
from contextlib import contextmanager
from sqlalchemy.engine import URL

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

    @contextmanager
    def transaction(self):
        """Open a transaction that commits on success, rolls back on failure."""
        with self.engine.begin() as conn:
            yield conn

    def load_query(self, sql, params=None, conn=None):
        """Load data from db into a df in memory"""
        if conn is not None:
            return pd.read_sql_query(text(sql), conn, params=params)
        with self.connect_to_database() as local_conn:
            return pd.read_sql_query(text(sql), local_conn, params=params)
    
    def minibatch_load_data(self, sql, limit=10000, offset=0, params=None) -> pd.DataFrame:
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

    def pandas_to_sql(self, user_input: pd.Series | pd.DataFrame, table_name: str, conn=None):
        """Convert pandas df to sql"""
        target_conn = conn if conn is not None else self.engine
        user_input.to_sql(name=table_name, con=target_conn, if_exists='append', index=False)

    def execute(self, sql, params=None, conn=None):
        """Execute sql queries to the connected database"""
        query = text(sql)
        if conn is not None:
            result = conn.execute(query, params or {})
            return result.rowcount
        with self.connect_to_database() as local_conn:
            result = local_conn.execute(query, params or {})
            local_conn.commit()
            return result.rowcount

    def execute_script(self, sql_script: str, params=None, conn=None):
        """Execute a multi-statement SQL script sequentially."""
        statements = [stmt.strip() for stmt in sql_script.split(";") if stmt.strip()]

        def _run(target_conn):
            for stmt in statements:
                target_conn.execute(text(stmt), params or {})

        if conn is not None:
            _run(conn)
            return
        with self.connect_to_database() as local_conn:
            _run(local_conn)
            local_conn.commit()

def create_database_manager() -> Database:
    """Create a database manager"""
    dbname = os.getenv('DATABASENAME')
    dbuser = os.getenv('DBUSER', 'postgres')
    dbpassword = os.getenv('DBPASSWORD')
    dbhost = os.getenv('DBHOST', 'localhost')
    dbport = os.getenv('DBPORT', 5432)

    return Database(dbname, dbuser, dbpassword, dbhost, dbport)
