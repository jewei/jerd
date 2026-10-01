<?php
header('Content-Type: application/json');
echo json_encode([
    'proof' => 'jerd-php-executed',
    'sapi' => PHP_SAPI,
    'version' => PHP_VERSION,
    'answer' => 6 * 7,
]);
