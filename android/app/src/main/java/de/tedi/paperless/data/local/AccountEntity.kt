package de.tedi.paperless.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "accounts")
data class AccountEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val serverUrl: String,
    val username: String,
    val isActive: Boolean = false
)
