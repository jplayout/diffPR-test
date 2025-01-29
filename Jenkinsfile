def IsMsiGenRelated() {
    try {
        sh 'git diff '
        return true
    }
    catch(Exception e) {
        return false
    }
    // Should never happen    
    return false
}

node(){
    if (IsMsiGenRelated()) {
        sh 'echo true'
    }
}