package de.tedi.paperless.data.local

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface AccountDao {
    @Query("SELECT * FROM accounts")
    fun observeAll(): Flow<List<AccountEntity>>

    @Query("SELECT * FROM accounts WHERE isActive = 1 LIMIT 1")
    suspend fun getActive(): AccountEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(account: AccountEntity): Long

    @Query("UPDATE accounts SET isActive = 0")
    suspend fun clearActive()

    @Query("UPDATE accounts SET isActive = 1 WHERE id = :id")
    suspend fun setActive(id: Long)

    @Delete
    suspend fun delete(account: AccountEntity)
}
