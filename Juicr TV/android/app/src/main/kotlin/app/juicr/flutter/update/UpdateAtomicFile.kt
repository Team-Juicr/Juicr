package app.juicr.flutter.update

import java.io.File

internal fun recoverUpdateFile(target: File) {
    val backup = File(target.parentFile, "${target.name}.bak")
    if (target.isFile) {
        backup.delete()
        return
    }
    if (backup.isFile && !backup.renameTo(target)) {
        throw IllegalStateException("Unable to recover update state")
    }
}

internal fun commitUpdateFile(temporary: File, target: File) {
    require(temporary.parentFile == target.parentFile)
    require(temporary.isFile)
    val backup = File(target.parentFile, "${target.name}.bak")
    recoverUpdateFile(target)
    backup.delete()
    if (target.exists() && !target.renameTo(backup)) {
        throw IllegalStateException("Unable to preserve update state")
    }
    if (!temporary.renameTo(target)) {
        if (backup.isFile) backup.renameTo(target)
        throw IllegalStateException("Unable to commit update state")
    }
    backup.delete()
}
